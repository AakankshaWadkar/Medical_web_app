-- Migration: 20260106000000_hr_payroll.sql
-- Description: Stage (e) HR & Payroll - Shifts, Employees, Attendance, Leaves, Holidays, Expenses, Salary Structures, Payroll, Payslips, HR Letters, Policies
-- Conventions: tenant_id uuid not null, apply_tenant_rls, numeric(14,2), timestamptz, check constraints

--------------------------------------------------------------------------------
-- 1. Shifts
--------------------------------------------------------------------------------
create table public.shifts (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references public.tenants(id) on delete cascade,
  name text not null,
  start_time time not null,
  end_time time not null,
  grace_period_minutes integer not null default 0 check (grace_period_minutes >= 0),
  is_night_shift boolean not null default false,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  deleted_at timestamptz,
  version bigint not null default 1,
  constraint uq_shifts_tenant_name unique (tenant_id, name)
);

call public.apply_tenant_rls('public.shifts');

--------------------------------------------------------------------------------
-- 2. Employees
--------------------------------------------------------------------------------
create table public.employees (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references public.tenants(id) on delete cascade,
  user_id uuid references public.app_users(id) on delete set null,
  branch_id uuid references public.branches(id) on delete set null,
  department_id uuid references public.departments(id) on delete set null,
  employee_code text not null,
  first_name text not null,
  last_name text,
  gender text check (gender is null or gender in ('male', 'female', 'other')),
  date_of_birth date,
  date_of_joining date not null default current_date,
  designation text,
  pan_no text,
  aadhar_no text,
  uan_no text,
  bank_name text,
  bank_account_no text,
  bank_ifsc text,
  marital_status text check (marital_status is null or marital_status in ('single', 'married', 'divorced', 'widowed', 'other')),
  status text not null default 'active' check (status in ('active', 'probation', 'resigned', 'terminated')),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  deleted_at timestamptz,
  version bigint not null default 1,
  constraint uq_employees_tenant_code unique (tenant_id, employee_code),
  constraint uq_employees_tenant_user unique (tenant_id, user_id)
);

call public.apply_tenant_rls('public.employees');
create index idx_employees_branch on public.employees (tenant_id, branch_id);
create index idx_employees_department on public.employees (tenant_id, department_id);
create index idx_employees_status on public.employees (tenant_id, status);

--------------------------------------------------------------------------------
-- 3. Employee Shifts
--------------------------------------------------------------------------------
create table public.employee_shifts (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references public.tenants(id) on delete cascade,
  employee_id uuid not null references public.employees(id) on delete cascade,
  shift_id uuid not null references public.shifts(id) on delete cascade,
  effective_from date not null default current_date,
  effective_to date,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  deleted_at timestamptz,
  version bigint not null default 1
);

call public.apply_tenant_rls('public.employee_shifts');
create index idx_emp_shifts_composite on public.employee_shifts (tenant_id, employee_id, effective_from);
create index idx_emp_shifts_shift on public.employee_shifts (tenant_id, shift_id);

--------------------------------------------------------------------------------
-- 4. Attendance
--------------------------------------------------------------------------------
create table public.attendance (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references public.tenants(id) on delete cascade,
  employee_id uuid not null references public.employees(id) on delete cascade,
  attendance_date date not null default current_date,
  shift_id uuid references public.shifts(id) on delete set null,
  check_in_time timestamptz,
  check_out_time timestamptz,
  check_in_latitude double precision,
  check_in_longitude double precision,
  check_out_latitude double precision,
  check_out_longitude double precision,
  status text not null default 'present' check (status in ('present', 'half_day', 'absent', 'on_leave', 'field_duty', 'holiday')),
  work_hours numeric(5,2) not null default 0.00 check (work_hours >= 0),
  remarks text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  deleted_at timestamptz,
  version bigint not null default 1,
  constraint uq_attendance_emp_date unique (tenant_id, employee_id, attendance_date)
);

call public.apply_tenant_rls('public.attendance');
create index idx_attendance_shift on public.attendance (tenant_id, shift_id);
create index idx_attendance_date on public.attendance (tenant_id, attendance_date desc);

--------------------------------------------------------------------------------
-- 5. Attendance Logs
--------------------------------------------------------------------------------
create table public.attendance_logs (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references public.tenants(id) on delete cascade,
  attendance_id uuid references public.attendance(id) on delete set null,
  employee_id uuid not null references public.employees(id) on delete cascade,
  punch_time timestamptz not null default now(),
  punch_type text not null check (punch_type in ('in', 'out')),
  latitude double precision,
  longitude double precision,
  device_info text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  deleted_at timestamptz,
  version bigint not null default 1
);

call public.apply_tenant_rls('public.attendance_logs');
create index idx_attendance_logs_emp_time on public.attendance_logs (tenant_id, employee_id, punch_time desc);
create index idx_attendance_logs_attendance on public.attendance_logs (tenant_id, attendance_id);

--------------------------------------------------------------------------------
-- 6. Leave Types
--------------------------------------------------------------------------------
create table public.leave_types (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references public.tenants(id) on delete cascade,
  code text not null,
  name text not null,
  days_per_year numeric(5,1) not null default 0.0 check (days_per_year >= 0),
  is_paid boolean not null default true,
  is_encashable boolean not null default false,
  carry_forward_days integer not null default 0 check (carry_forward_days >= 0),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  deleted_at timestamptz,
  version bigint not null default 1,
  constraint uq_leave_types_tenant_code unique (tenant_id, code)
);

call public.apply_tenant_rls('public.leave_types');

--------------------------------------------------------------------------------
-- 7. Leave Balances
--------------------------------------------------------------------------------
create table public.leave_balances (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references public.tenants(id) on delete cascade,
  employee_id uuid not null references public.employees(id) on delete cascade,
  leave_type_id uuid not null references public.leave_types(id) on delete cascade,
  year integer not null check (year >= 2000),
  allocated_days numeric(5,1) not null default 0.0 check (allocated_days >= 0),
  used_days numeric(5,1) not null default 0.0 check (used_days >= 0),
  balance_days numeric(5,1) not null default 0.0 check (balance_days >= 0),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  deleted_at timestamptz,
  version bigint not null default 1,
  constraint uq_leave_balances_emp_type_year unique (tenant_id, employee_id, leave_type_id, year)
);

call public.apply_tenant_rls('public.leave_balances');
create index idx_leave_balances_type on public.leave_balances (tenant_id, leave_type_id);

--------------------------------------------------------------------------------
-- 8. Leaves
--------------------------------------------------------------------------------
create table public.leaves (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references public.tenants(id) on delete cascade,
  employee_id uuid not null references public.employees(id) on delete cascade,
  leave_type_id uuid not null references public.leave_types(id) on delete restrict,
  start_date date not null,
  end_date date not null,
  total_days numeric(5,1) not null check (total_days > 0),
  reason text,
  status text not null default 'pending' check (status in ('pending', 'approved', 'rejected', 'cancelled')),
  approved_by_employee_id uuid references public.employees(id) on delete set null,
  approved_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  deleted_at timestamptz,
  version bigint not null default 1,
  constraint ck_leaves_dates check (end_date >= start_date)
);

call public.apply_tenant_rls('public.leaves');
create index idx_leaves_emp_dates on public.leaves (tenant_id, employee_id, start_date);
create index idx_leaves_type on public.leaves (tenant_id, leave_type_id);
create index idx_leaves_approver on public.leaves (tenant_id, approved_by_employee_id);

--------------------------------------------------------------------------------
-- 9. Holidays
--------------------------------------------------------------------------------
create table public.holidays (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references public.tenants(id) on delete cascade,
  holiday_name text not null,
  holiday_date date not null,
  holiday_type text not null default 'company' check (holiday_type in ('national', 'regional', 'company')),
  is_restricted boolean not null default false,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  deleted_at timestamptz,
  version bigint not null default 1,
  constraint uq_holidays_tenant_date_name unique (tenant_id, holiday_date, holiday_name)
);

call public.apply_tenant_rls('public.holidays');
create index idx_holidays_date on public.holidays (tenant_id, holiday_date);

--------------------------------------------------------------------------------
-- 10. Expense Categories
--------------------------------------------------------------------------------
create table public.expense_categories (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references public.tenants(id) on delete cascade,
  code text not null,
  name text not null,
  max_daily_limit numeric(14,2) not null default 0.00 check (max_daily_limit >= 0),
  requires_receipt boolean not null default false,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  deleted_at timestamptz,
  version bigint not null default 1,
  constraint uq_expense_categories_code unique (tenant_id, code)
);

call public.apply_tenant_rls('public.expense_categories');

--------------------------------------------------------------------------------
-- 11. Expense Claims
--------------------------------------------------------------------------------
create table public.expense_claims (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references public.tenants(id) on delete cascade,
  claim_number text not null,
  employee_id uuid not null references public.employees(id) on delete cascade,
  submission_date date not null default current_date,
  claim_period_start date not null,
  claim_period_end date not null,
  total_amount numeric(14,2) not null default 0.00 check (total_amount >= 0),
  approved_amount numeric(14,2) not null default 0.00 check (approved_amount >= 0),
  status text not null default 'draft' check (status in ('draft', 'submitted', 'approved', 'partially_approved', 'rejected', 'paid')),
  approved_by_employee_id uuid references public.employees(id) on delete set null,
  approved_at timestamptz,
  paid_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  deleted_at timestamptz,
  version bigint not null default 1,
  constraint uq_expense_claims_number unique (tenant_id, claim_number),
  constraint ck_expense_claims_dates check (claim_period_end >= claim_period_start)
);

call public.apply_tenant_rls('public.expense_claims');
create index idx_expense_claims_emp on public.expense_claims (tenant_id, employee_id);
create index idx_expense_claims_approver on public.expense_claims (tenant_id, approved_by_employee_id);

--------------------------------------------------------------------------------
-- 12. Expenses
--------------------------------------------------------------------------------
create table public.expenses (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references public.tenants(id) on delete cascade,
  employee_id uuid not null references public.employees(id) on delete cascade,
  expense_date date not null default current_date,
  category_id uuid not null references public.expense_categories(id) on delete restrict,
  amount numeric(14,2) not null check (amount > 0),
  receipt_file_id uuid references public.file_storage(id) on delete set null,
  description text,
  status text not null default 'pending' check (status in ('pending', 'approved', 'rejected')),
  claim_id uuid references public.expense_claims(id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  deleted_at timestamptz,
  version bigint not null default 1
);

call public.apply_tenant_rls('public.expenses');
create index idx_expenses_emp_date on public.expenses (tenant_id, employee_id, expense_date desc);
create index idx_expenses_category on public.expenses (tenant_id, category_id);
create index idx_expenses_claim on public.expenses (tenant_id, claim_id);
create index idx_expenses_receipt on public.expenses (tenant_id, receipt_file_id);

--------------------------------------------------------------------------------
-- 13. Salary Structures
--------------------------------------------------------------------------------
create table public.salary_structures (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references public.tenants(id) on delete cascade,
  code text not null,
  name text not null,
  description text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  deleted_at timestamptz,
  version bigint not null default 1,
  constraint uq_salary_structures_code unique (tenant_id, code)
);

call public.apply_tenant_rls('public.salary_structures');

--------------------------------------------------------------------------------
-- 14. Salary Structure Components
--------------------------------------------------------------------------------
create table public.salary_structure_components (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references public.tenants(id) on delete cascade,
  salary_structure_id uuid not null references public.salary_structures(id) on delete cascade,
  component_name text not null,
  component_type text not null check (component_type in ('earning', 'deduction')),
  calculation_type text not null check (calculation_type in ('fixed', 'percentage_of_basic')),
  amount_or_formula text not null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  deleted_at timestamptz,
  version bigint not null default 1
);

call public.apply_tenant_rls('public.salary_structure_components');
create index idx_sal_components_structure on public.salary_structure_components (tenant_id, salary_structure_id);

--------------------------------------------------------------------------------
-- 15. Employee Salaries
--------------------------------------------------------------------------------
create table public.employee_salaries (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references public.tenants(id) on delete cascade,
  employee_id uuid not null references public.employees(id) on delete cascade,
  salary_structure_id uuid not null references public.salary_structures(id) on delete restrict,
  ctc numeric(14,2) not null check (ctc >= 0),
  gross_salary numeric(14,2) not null check (gross_salary >= 0),
  net_salary numeric(14,2) not null check (net_salary >= 0),
  effective_from date not null default current_date,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  deleted_at timestamptz,
  version bigint not null default 1
);

call public.apply_tenant_rls('public.employee_salaries');
create index idx_emp_salary_composite on public.employee_salaries (tenant_id, employee_id, effective_from desc);
create index idx_emp_salary_structure on public.employee_salaries (tenant_id, salary_structure_id);

--------------------------------------------------------------------------------
-- 16. Payrolls
--------------------------------------------------------------------------------
create table public.payrolls (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references public.tenants(id) on delete cascade,
  payroll_month integer not null check (payroll_month between 1 and 12),
  payroll_year integer not null check (payroll_year >= 2000),
  total_employees integer not null default 0 check (total_employees >= 0),
  total_gross numeric(14,2) not null default 0.00 check (total_gross >= 0),
  total_deductions numeric(14,2) not null default 0.00 check (total_deductions >= 0),
  total_net numeric(14,2) not null default 0.00 check (total_net >= 0),
  status text not null default 'draft' check (status in ('draft', 'calculated', 'approved', 'paid')),
  processed_by_user_id uuid references public.app_users(id) on delete set null,
  processed_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  deleted_at timestamptz,
  version bigint not null default 1,
  constraint uq_payrolls_period unique (tenant_id, payroll_month, payroll_year)
);

call public.apply_tenant_rls('public.payrolls');
create index idx_payrolls_processed_by on public.payrolls (tenant_id, processed_by_user_id);

--------------------------------------------------------------------------------
-- 17. Payslips
--------------------------------------------------------------------------------
create table public.payslips (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references public.tenants(id) on delete cascade,
  payroll_id uuid not null references public.payrolls(id) on delete cascade,
  employee_id uuid not null references public.employees(id) on delete cascade,
  gross_pay numeric(14,2) not null default 0.00 check (gross_pay >= 0),
  total_deductions numeric(14,2) not null default 0.00 check (total_deductions >= 0),
  net_pay numeric(14,2) not null default 0.00 check (net_pay >= 0),
  basic numeric(14,2) not null default 0.00 check (basic >= 0),
  hra numeric(14,2) not null default 0.00 check (hra >= 0),
  allowances numeric(14,2) not null default 0.00 check (allowances >= 0),
  pf numeric(14,2) not null default 0.00 check (pf >= 0),
  esic numeric(14,2) not null default 0.00 check (esic >= 0),
  professional_tax numeric(14,2) not null default 0.00 check (professional_tax >= 0),
  tds numeric(14,2) not null default 0.00 check (tds >= 0),
  payslip_pdf_file_id uuid references public.file_storage(id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  deleted_at timestamptz,
  version bigint not null default 1,
  constraint uq_payslips_payroll_employee unique (tenant_id, payroll_id, employee_id)
);

call public.apply_tenant_rls('public.payslips');
create index idx_payslips_employee on public.payslips (tenant_id, employee_id);
create index idx_payslips_file on public.payslips (tenant_id, payslip_pdf_file_id);

--------------------------------------------------------------------------------
-- 18. HR Letters
--------------------------------------------------------------------------------
create table public.hr_letters (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references public.tenants(id) on delete cascade,
  employee_id uuid not null references public.employees(id) on delete cascade,
  letter_type text not null check (letter_type in ('appointment', 'appraisal', 'confirmation', 'relieving', 'warning', 'other')),
  title text not null,
  issue_date date not null default current_date,
  file_id uuid references public.file_storage(id) on delete set null,
  issued_by_user_id uuid references public.app_users(id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  deleted_at timestamptz,
  version bigint not null default 1
);

call public.apply_tenant_rls('public.hr_letters');
create index idx_hr_letters_emp on public.hr_letters (tenant_id, employee_id);
create index idx_hr_letters_file on public.hr_letters (tenant_id, file_id);
create index idx_hr_letters_issuer on public.hr_letters (tenant_id, issued_by_user_id);

--------------------------------------------------------------------------------
-- 19. Company Policies
--------------------------------------------------------------------------------
create table public.company_policies (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references public.tenants(id) on delete cascade,
  title text not null,
  category text not null,
  effective_date date not null default current_date,
  file_id uuid references public.file_storage(id) on delete set null,
  is_active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  deleted_at timestamptz,
  version bigint not null default 1
);

call public.apply_tenant_rls('public.company_policies');
create index idx_company_policies_category on public.company_policies (tenant_id, category);
create index idx_company_policies_file on public.company_policies (tenant_id, file_id);
