from pydantic import BaseModel, ConfigDict, EmailStr, Field


class LoginRequest(BaseModel):
    email: EmailStr
    password: str = Field(min_length=8, max_length=128)


class UserResponse(BaseModel):
    id: int
    name: str
    email: EmailStr
    role: str


class TokenResponse(BaseModel):
    access_token: str
    token_type: str = "bearer"
    user: UserResponse


class EmployeeBase(BaseModel):
    first_name: str = Field(min_length=1, max_length=100)
    last_name: str = Field(default="", max_length=100)
    email: EmailStr
    phone: str = Field(default="", max_length=40)
    image: str = ""
    title: str = Field(default="", max_length=120)
    department: str = Field(default="Unassigned", min_length=1, max_length=120)
    address: str = Field(default="", max_length=255)
    city: str = Field(default="", max_length=120)
    state: str = Field(default="", max_length=120)
    postal_code: str = Field(default="", max_length=30)
    country: str = Field(default="", max_length=120)


class EmployeeCreate(EmployeeBase):
    pass


class EmployeeUpdate(BaseModel):
    first_name: str | None = Field(default=None, min_length=1, max_length=100)
    last_name: str | None = Field(default=None, max_length=100)
    email: EmailStr | None = None
    phone: str | None = Field(default=None, max_length=40)
    image: str | None = None
    title: str | None = Field(default=None, max_length=120)
    department: str | None = Field(default=None, min_length=1, max_length=120)
    address: str | None = Field(default=None, max_length=255)
    city: str | None = Field(default=None, max_length=120)
    state: str | None = Field(default=None, max_length=120)
    postal_code: str | None = Field(default=None, max_length=30)
    country: str | None = Field(default=None, max_length=120)


class EmployeeResponse(EmployeeBase):
    model_config = ConfigDict(from_attributes=True)
    id: int


class DepartmentStat(BaseModel):
    department: str
    count: int


class DashboardStats(BaseModel):
    total_employees: int
    total_departments: int
    departments: list[DepartmentStat]
