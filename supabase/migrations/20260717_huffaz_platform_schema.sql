-- =============================================
-- منصة حفّاظ - Huffaz Platform Database Schema
-- =============================================

-- Enable UUID extension
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";

-- =============================================
-- TABLES
-- =============================================

-- users
CREATE TABLE users (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  name TEXT NOT NULL,
  email TEXT NOT NULL UNIQUE,
  password TEXT NOT NULL,
  role TEXT NOT NULL CHECK (role IN ('admin', 'teacher', 'student')),
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- programs
CREATE TABLE programs (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  name TEXT NOT NULL,
  total_hadiths INTEGER NOT NULL,
  total_days INTEGER NOT NULL
);

-- teachers
CREATE TABLE teachers (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  max_students INTEGER NOT NULL DEFAULT 30
);

-- students
CREATE TABLE students (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  teacher_id UUID REFERENCES teachers(id) ON DELETE SET NULL,
  program_id UUID REFERENCES programs(id) ON DELETE SET NULL,
  join_date DATE NOT NULL DEFAULT CURRENT_DATE,
  status TEXT NOT NULL CHECK (status IN ('active', 'paused', 'graduated', 'withdrawn')) DEFAULT 'active',
  memorized_hadiths INTEGER NOT NULL DEFAULT 0
);

-- student_plans
CREATE TABLE student_plans (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  student_id UUID NOT NULL REFERENCES students(id) ON DELETE CASCADE,
  day_number INTEGER NOT NULL,
  date DATE NOT NULL,
  memorization_target INTEGER,
  repetition_count INTEGER,
  linking_from INTEGER,
  linking_to INTEGER,
  self_review TEXT,
  is_completed BOOLEAN NOT NULL DEFAULT FALSE
);

-- recitation_sessions
CREATE TABLE recitation_sessions (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  student_id UUID NOT NULL REFERENCES students(id) ON DELETE CASCADE,
  teacher_id UUID NOT NULL REFERENCES teachers(id) ON DELETE CASCADE,
  date DATE NOT NULL DEFAULT CURRENT_DATE,
  hadith_from INTEGER,
  hadith_to INTEGER,
  folder TEXT,
  repetitions INTEGER,
  linking_from INTEGER,
  linking_to INTEGER,
  self_review_notes TEXT,
  full_mark_errors INTEGER DEFAULT 0,
  half_mark_errors INTEGER DEFAULT 0,
  quarter_mark_errors INTEGER DEFAULT 0,
  score NUMERIC(5,2),
  notes TEXT
);

-- attendance
CREATE TABLE attendance (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  student_id UUID NOT NULL REFERENCES students(id) ON DELETE CASCADE,
  session_id UUID REFERENCES recitation_sessions(id) ON DELETE SET NULL,
  date DATE NOT NULL DEFAULT CURRENT_DATE,
  is_present BOOLEAN NOT NULL DEFAULT TRUE
);

-- periodic_exams
CREATE TABLE periodic_exams (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  student_id UUID NOT NULL REFERENCES students(id) ON DELETE CASCADE,
  exam_name TEXT NOT NULL,
  score NUMERIC(5,2),
  date DATE NOT NULL DEFAULT CURRENT_DATE,
  notes TEXT
);

-- daily_reviews
CREATE TABLE daily_reviews (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  student_id UUID NOT NULL REFERENCES students(id) ON DELETE CASCADE,
  date DATE NOT NULL DEFAULT CURRENT_DATE,
  is_completed BOOLEAN NOT NULL DEFAULT FALSE,
  completed_tasks JSONB
);

-- =============================================
-- INDEXES
-- =============================================

CREATE INDEX idx_teachers_user_id ON teachers(user_id);
CREATE INDEX idx_students_user_id ON students(user_id);
CREATE INDEX idx_students_teacher_id ON students(teacher_id);
CREATE INDEX idx_students_program_id ON students(program_id);
CREATE INDEX idx_student_plans_student_id ON student_plans(student_id);
CREATE INDEX idx_recitation_sessions_student_id ON recitation_sessions(student_id);
CREATE INDEX idx_recitation_sessions_teacher_id ON recitation_sessions(teacher_id);
CREATE INDEX idx_attendance_student_id ON attendance(student_id);
CREATE INDEX idx_periodic_exams_student_id ON periodic_exams(student_id);
CREATE INDEX idx_daily_reviews_student_id ON daily_reviews(student_id);

-- =============================================
-- ROW LEVEL SECURITY
-- =============================================

ALTER TABLE users ENABLE ROW LEVEL SECURITY;
ALTER TABLE teachers ENABLE ROW LEVEL SECURITY;
ALTER TABLE students ENABLE ROW LEVEL SECURITY;
ALTER TABLE programs ENABLE ROW LEVEL SECURITY;
ALTER TABLE student_plans ENABLE ROW LEVEL SECURITY;
ALTER TABLE recitation_sessions ENABLE ROW LEVEL SECURITY;
ALTER TABLE attendance ENABLE ROW LEVEL SECURITY;
ALTER TABLE periodic_exams ENABLE ROW LEVEL SECURITY;
ALTER TABLE daily_reviews ENABLE ROW LEVEL SECURITY;

-- Helper functions
CREATE OR REPLACE FUNCTION get_current_user_role()
RETURNS TEXT AS $$
  SELECT role FROM users WHERE id = auth.uid()
$$ LANGUAGE sql SECURITY DEFINER STABLE;

CREATE OR REPLACE FUNCTION get_teacher_id_for_current_user()
RETURNS UUID AS $$
  SELECT id FROM teachers WHERE user_id = auth.uid()
$$ LANGUAGE sql SECURITY DEFINER STABLE;

CREATE OR REPLACE FUNCTION get_student_id_for_current_user()
RETURNS UUID AS $$
  SELECT id FROM students WHERE user_id = auth.uid()
$$ LANGUAGE sql SECURITY DEFINER STABLE;

-- RLS POLICIES: users
CREATE POLICY "admin_all_users" ON users
  FOR ALL USING (get_current_user_role() = 'admin');

CREATE POLICY "self_view_users" ON users
  FOR SELECT USING (id = auth.uid());

-- RLS POLICIES: programs
CREATE POLICY "admin_all_programs" ON programs
  FOR ALL USING (get_current_user_role() = 'admin');

CREATE POLICY "teacher_student_read_programs" ON programs
  FOR SELECT USING (get_current_user_role() IN ('teacher', 'student'));

-- RLS POLICIES: teachers
CREATE POLICY "admin_all_teachers" ON teachers
  FOR ALL USING (get_current_user_role() = 'admin');

CREATE POLICY "teacher_self" ON teachers
  FOR SELECT USING (user_id = auth.uid());

-- RLS POLICIES: students
CREATE POLICY "admin_all_students" ON students
  FOR ALL USING (get_current_user_role() = 'admin');

CREATE POLICY "teacher_own_students" ON students
  FOR SELECT USING (
    get_current_user_role() = 'teacher'
    AND teacher_id = get_teacher_id_for_current_user()
  );

CREATE POLICY "student_self" ON students
  FOR SELECT USING (
    get_current_user_role() = 'student'
    AND user_id = auth.uid()
  );

-- RLS POLICIES: student_plans
CREATE POLICY "admin_all_student_plans" ON student_plans
  FOR ALL USING (get_current_user_role() = 'admin');

CREATE POLICY "teacher_student_plans" ON student_plans
  FOR SELECT USING (
    get_current_user_role() = 'teacher'
    AND student_id IN (
      SELECT id FROM students WHERE teacher_id = get_teacher_id_for_current_user()
    )
  );

CREATE POLICY "student_own_plans" ON student_plans
  FOR ALL USING (
    get_current_user_role() = 'student'
    AND student_id = get_student_id_for_current_user()
  );

-- RLS POLICIES: recitation_sessions
CREATE POLICY "admin_all_recitation_sessions" ON recitation_sessions
  FOR ALL USING (get_current_user_role() = 'admin');

CREATE POLICY "teacher_recitation_sessions" ON recitation_sessions
  FOR ALL USING (
    get_current_user_role() = 'teacher'
    AND teacher_id = get_teacher_id_for_current_user()
  );

CREATE POLICY "student_own_recitation_sessions" ON recitation_sessions
  FOR SELECT USING (
    get_current_user_role() = 'student'
    AND student_id = get_student_id_for_current_user()
  );

-- RLS POLICIES: attendance
CREATE POLICY "admin_all_attendance" ON attendance
  FOR ALL USING (get_current_user_role() = 'admin');

CREATE POLICY "teacher_attendance" ON attendance
  FOR ALL USING (
    get_current_user_role() = 'teacher'
    AND student_id IN (
      SELECT id FROM students WHERE teacher_id = get_teacher_id_for_current_user()
    )
  );

CREATE POLICY "student_own_attendance" ON attendance
  FOR SELECT USING (
    get_current_user_role() = 'student'
    AND student_id = get_student_id_for_current_user()
  );

-- RLS POLICIES: periodic_exams
CREATE POLICY "admin_all_periodic_exams" ON periodic_exams
  FOR ALL USING (get_current_user_role() = 'admin');

CREATE POLICY "teacher_periodic_exams" ON periodic_exams
  FOR ALL USING (
    get_current_user_role() = 'teacher'
    AND student_id IN (
      SELECT id FROM students WHERE teacher_id = get_teacher_id_for_current_user()
    )
  );

CREATE POLICY "student_own_periodic_exams" ON periodic_exams
  FOR SELECT USING (
    get_current_user_role() = 'student'
    AND student_id = get_student_id_for_current_user()
  );

-- RLS POLICIES: daily_reviews
CREATE POLICY "admin_all_daily_reviews" ON daily_reviews
  FOR ALL USING (get_current_user_role() = 'admin');

CREATE POLICY "teacher_daily_reviews" ON daily_reviews
  FOR SELECT USING (
    get_current_user_role() = 'teacher'
    AND student_id IN (
      SELECT id FROM students WHERE teacher_id = get_teacher_id_for_current_user()
    )
  );

CREATE POLICY "student_own_daily_reviews" ON daily_reviews
  FOR ALL USING (
    get_current_user_role() = 'student'
    AND student_id = get_student_id_for_current_user()
  );
