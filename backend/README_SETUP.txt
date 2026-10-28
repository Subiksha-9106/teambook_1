TEAMBOOK BACKEND SETUP (Windows PowerShell)

This folder is to be copied into your existing project:
C:\Users\user\Downloads\TeamBook_Flutter_RoleBased_DepartmentFilters\TeamBook_Flutter_Mobile_Source\backend

1. Install PostgreSQL. In pgAdmin or psql, create a database and user:
   CREATE USER teambook_user WITH PASSWORD 'choose_a_strong_password';
   CREATE DATABASE teambook OWNER teambook_user;

2. Open PowerShell in the backend folder:
   py -m venv .venv
   .\.venv\Scripts\Activate.ps1
   python -m pip install --upgrade pip
   pip install -r requirements.txt

3. Copy .env.example to .env. Edit DATABASE_URL so the password matches the PostgreSQL user.
   Generate a long random JWT_SECRET (at least 32 characters). Change ADMIN_PASSWORD.
   Do not commit .env to GitHub.

4. Install the email validation dependency required by Pydantic:
   pip install email-validator
   (Alternatively add `email-validator>=2.0,<3.0` to requirements.txt.)

5. Run from the backend folder:
   uvicorn main:app --reload --host 0.0.0.0 --port 8000

6. Check:
   http://127.0.0.1:8000/health
   http://127.0.0.1:8000/docs

API ROUTES
POST   /auth/login             login and receive bearer token
GET    /auth/me                current signed-in account
GET    /employees              list/search/filter/sort (login required)
POST   /employees              add employee (Admin only)
PATCH  /employees/{id}         edit employee (Admin only)
DELETE /employees/{id}         delete employee (Admin only)
GET    /stats                  total employee and department counts
GET    /employees/export.csv   export employee list (Admin only)

IMPORTANT
- These files provide the backend. The current Flutter lib/main.dart still uses demo/local authentication and DummyJSON.
  It must be updated to call this backend before the app uses PostgreSQL records.
- Create your first admin from ADMIN_EMAIL and ADMIN_PASSWORD in .env. Do not allow a client to choose its own admin role.
- The app uses local browser storage for current demo state. Once connected, server-side employee records will be stored in PostgreSQL.
