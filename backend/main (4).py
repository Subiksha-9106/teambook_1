import csv
import io
import os
from contextlib import asynccontextmanager
from fastapi import Depends, FastAPI, HTTPException, Query, Response, status
from fastapi.middleware.cors import CORSMiddleware
from sqlalchemy import func, or_, select
from sqlalchemy.exc import IntegrityError
from sqlalchemy.orm import Session
from database import Base, engine, get_db
from models import Employee, User
from schemas import (
    DashboardStats, DepartmentStat, EmployeeCreate, EmployeeResponse,
    EmployeeUpdate, LoginRequest, TokenResponse, UserResponse,
)
from security import create_access_token, hash_password, require_admin, verify_password, get_current_user


def seed_admin():
    email = os.getenv("ADMIN_EMAIL", "admin@teambook.local").strip().lower()
    password = os.getenv("ADMIN_PASSWORD", "")
    name = os.getenv("ADMIN_NAME", "TeamBook Admin")
    if not password:
        print("ADMIN_PASSWORD is empty: admin account was not created.")
        return
    with Session(engine) as db:
        existing = db.scalar(select(User).where(User.email == email))
        if existing is None:
            db.add(User(name=name, email=email, password_hash=hash_password(password), role="admin"))
            db.commit()


@asynccontextmanager
async def lifespan(app: FastAPI):
    Base.metadata.create_all(bind=engine)
    seed_admin()
    yield


app = FastAPI(title="TeamBook API", version="1.0.0", lifespan=lifespan)
origins = [x.strip() for x in os.getenv("CORS_ORIGINS", "http://localhost:8080").split(",") if x.strip()]
app.add_middleware(
    CORSMiddleware,
    allow_origins=origins,
    allow_credentials=True,
    allow_methods=["GET", "POST", "PATCH", "DELETE", "OPTIONS"],
    allow_headers=["Authorization", "Content-Type"],
)


@app.get("/health")
def health():
    return {"status": "ok", "service": "TeamBook API"}


@app.post("/auth/login", response_model=TokenResponse)
def login(payload: LoginRequest, db: Session = Depends(get_db)):
    email = str(payload.email).strip().lower()
    user = db.scalar(select(User).where(User.email == email))
    if not user or not user.is_active or not verify_password(payload.password, user.password_hash):
        raise HTTPException(status_code=401, detail="Email or password is incorrect")
    token = create_access_token(user)
    return {"access_token": token, "token_type": "bearer", "user": user}


@app.get("/auth/me", response_model=UserResponse)
def me(user: User = Depends(get_current_user)):
    return user


@app.get("/employees", response_model=list[EmployeeResponse])
def list_employees(
    q: str = Query(default="", max_length=120),
    department: str | None = None,
    title: str | None = None,
    sort: str = Query(default="name_asc", pattern="^(name_asc|name_desc|department)$"),
    db: Session = Depends(get_db),
    user: User = Depends(get_current_user),
):
    stmt = select(Employee)
    if q.strip():
        term = f"%{q.strip()}%"
        stmt = stmt.where(or_(
            Employee.first_name.ilike(term), Employee.last_name.ilike(term),
            Employee.email.ilike(term), Employee.title.ilike(term),
            Employee.department.ilike(term),
        ))
    if department and department != "All departments":
        stmt = stmt.where(Employee.department == department)
    if title and title != "All roles":
        stmt = stmt.where(Employee.title == title)
    if sort == "name_desc":
        stmt = stmt.order_by(Employee.last_name.desc(), Employee.first_name.desc())
    elif sort == "department":
        stmt = stmt.order_by(Employee.department.asc(), Employee.last_name.asc())
    else:
        stmt = stmt.order_by(Employee.last_name.asc(), Employee.first_name.asc())
    return list(db.scalars(stmt).all())


@app.post("/employees", response_model=EmployeeResponse, status_code=status.HTTP_201_CREATED)
def create_employee(
    payload: EmployeeCreate,
    db: Session = Depends(get_db),
    admin: User = Depends(require_admin),
):
    data = payload.model_dump()
    data["email"] = str(payload.email).lower()
    employee = Employee(**data)
    db.add(employee)
    try:
        db.commit()
        db.refresh(employee)
    except IntegrityError:
        db.rollback()
        raise HTTPException(status_code=409, detail="An employee with this email already exists")
    return employee


@app.patch("/employees/{employee_id}", response_model=EmployeeResponse)
def update_employee(
    employee_id: int,
    payload: EmployeeUpdate,
    db: Session = Depends(get_db),
    admin: User = Depends(require_admin),
):
    employee = db.get(Employee, employee_id)
    if not employee:
        raise HTTPException(status_code=404, detail="Employee not found")
    updates = payload.model_dump(exclude_unset=True)
    if "email" in updates and updates["email"] is not None:
        updates["email"] = str(updates["email"]).lower()
    for key, value in updates.items():
        setattr(employee, key, value)
    try:
        db.commit()
        db.refresh(employee)
    except IntegrityError:
        db.rollback()
        raise HTTPException(status_code=409, detail="An employee with this email already exists")
    return employee


@app.delete("/employees/{employee_id}", status_code=status.HTTP_204_NO_CONTENT)
def delete_employee(
    employee_id: int,
    db: Session = Depends(get_db),
    admin: User = Depends(require_admin),
):
    employee = db.get(Employee, employee_id)
    if not employee:
        raise HTTPException(status_code=404, detail="Employee not found")
    db.delete(employee)
    db.commit()
    return Response(status_code=status.HTTP_204_NO_CONTENT)


@app.get("/stats", response_model=DashboardStats)
def dashboard_stats(db: Session = Depends(get_db), user: User = Depends(get_current_user)):
    total = db.scalar(select(func.count(Employee.id))) or 0
    rows = db.execute(
        select(Employee.department, func.count(Employee.id))
        .group_by(Employee.department)
        .order_by(Employee.department.asc())
    ).all()
    departments = [DepartmentStat(department=name or "Unassigned", count=count) for name, count in rows]
    return DashboardStats(total_employees=total, total_departments=len(departments), departments=departments)


@app.get("/employees/export.csv")
def export_csv(db: Session = Depends(get_db), admin: User = Depends(require_admin)):
    employees = db.scalars(select(Employee).order_by(Employee.department, Employee.last_name, Employee.first_name)).all()
    output = io.StringIO()
    writer = csv.writer(output)
    writer.writerow(["ID", "First name", "Last name", "Email", "Phone", "Job role", "Department", "Address", "City", "State", "Postal code", "Country"])
    for e in employees:
        writer.writerow([e.id, e.first_name, e.last_name, e.email, e.phone, e.title, e.department, e.address, e.city, e.state, e.postal_code, e.country])
    return Response(
        content="\ufeff" + output.getvalue(),
        media_type="text/csv; charset=utf-8",
        headers={"Content-Disposition": 'attachment; filename="teambook_employees.csv"'},
    )
