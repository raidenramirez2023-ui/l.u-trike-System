# LuTrike: Laguna University Tricycle Queue Management Web Application

A responsive digital tricycle terminal and queue management web application designed specifically for **Laguna University (LU)** students and authorized tricycle drivers.

> [!NOTE]
> This application is an **independent student project proposal**. It does not assume official institutional integration or endorsement from Laguna University unless officially confirmed.

---

## 🌟 Key Features

### 🎓 1. Student Dashboard (Mobile-First)
- **Live Terminal Overview:** View terminal operating status, waiting tricycles, tricycles boarding, and tricycles ready to depart.
- **Tricycle Queue Cards:** Real-time visibility into queue positions (#01, #02, etc.), driver name, vehicle plate number, passenger count with seat bar visualization, and remaining seats.
- **Queue Progress Tracker:** Highlights the next vehicle to depart and indicates remaining passengers required by departure policy.
- **Estimated Departure Pace:** Displays calculated departure interval based on actual recorded departures (labeled as an estimate; requires minimum sample size).
- **In-App Realtime Notifications:** Alerts when tricycles are almost full, ready to depart, or when queue state changes.
- **Reporting & Feedback:** Submit reports for incorrect passenger counts, safety concerns, lost-and-found items, and general feedback for administrator review.
- **QR Code Deep-Linking:** Support for `/t/:terminalCode` deep links (e.g. `/t/MAIN`) for students scanning physical terminal signs.

### 🛺 2. Driver Dashboard (Touch-Friendly)
- **Fast Touch Controls:** Clear, large tap targets for adding (+1) and removing (-1) passengers with confirmation guards.
- **State Machine Actions:**
  - `Join Queue` (at back of queue based on server sequence).
  - `Mark Ready to Depart` (validated against the terminal's configured departure policy).
  - `Confirm Departure` (converts entry into a departed trip record; frees up the next vehicle in line).
  - `Arrived Back at Terminal` (rejoins queue at the back).
  - `Pause / Resume` (allows taking a temporary break; pauses must have 0 passengers).
  - `Leave Queue` (with required reason for audit).
- **Trip & Activity History:** Displays today's departed trips, passenger counts, wait durations, and queue actions.

### 🛡️ 3. Administrator Dashboard (Desktop & Mobile)
- **Operations Overview:** Real-time counters for registered students, active drivers, pending approvals, queue length, and departures today.
- **Driver & Vehicle Verification:** Review pending driver requests, inspect plate number and capacity, and approve or reject accounts.
- **Student Account Verification:** Format validation check for LU student numbers; administrators can officially verify or suspend accounts.
- **Audited Queue Corrections:** Authorised workflow to adjust invalid passenger counts or queue statuses, with mandatory recorded audit reasons.
- **Analytics & Departure Reports:** Peak departure hours and driver activity ranking generated exclusively from real trip records.

---

## 🏗️ System Architecture & Reliability

- **Frontend:** Flutter Web (responsive across mobile, tablet, and desktop).
- **Backend & Database:** Supabase (PostgreSQL 15+, Auth, Realtime, Row Level Security).
- **Concurrency & Atomicity:**
  - Every queue mutation invokes a `SECURITY DEFINER` Postgres function (`driver_passenger_delta`, `driver_confirm_departure`, etc.).
  - Transactions obtain a row-level lock (`SELECT ... FOR UPDATE`) on the terminal record, preventing race conditions.
  - Queue position is derived dynamically via `ROW_NUMBER() OVER (ORDER BY seq)` — **clients cannot submit or spoof queue order**.
  - Database `CHECK` constraints guarantee passenger counts never drop below 0 or exceed vehicle capacity.
- **Realtime Synchronization & Stale Detection:**
  - Supabase Realtime listens for database changes and triggers debounced updates.
  - Connection status badge indicates live or offline status.
  - Automatically alerts users when queue data is older than the configured threshold.

---

## 🚀 Setup & Installation

### Step 1: Set Up Supabase (Free Cloud Tier)
1. Go to [supabase.com](https://supabase.com) and create a free project.
2. In your Supabase dashboard, open the **SQL Editor**.
3. Run the migrations in order:
   - `supabase/migrations/0001_schema.sql` (Creates tables, enums, constraints, indexes).
   - `supabase/migrations/0002_auth_rls.sql` (Sets up auth triggers and Row Level Security).
   - `supabase/migrations/0003_queue_rpc.sql` (Installs server-side queue state machine and RPCs).
4. Run `supabase/seed_demo.sql` to populate sample Laguna University terminals.
5. In Supabase Dashboard, go to **Project Settings** > **API**:
   - Copy the **Project URL**.
   - Copy the **anon / public** key (never use the service-role key in the app).

### Step 2: Configure Environment Variables
Create a file named `env.json` in the root of the project:
```json
{
  "SUPABASE_URL": "https://your-project-id.supabase.co",
  "SUPABASE_ANON_KEY": "your-anon-public-key-here",
  "DEMO_MODE": "true"
}
```

### Step 3: Run the Web App
Make sure Flutter is installed, then launch in Chrome:
```powershell
flutter run -d chrome --dart-define-from-file=env.json
```

---

## 👥 Creating Demo User Accounts

### 1. Student Account
1. Open the web app and click **I'm a Student** > **Register**.
2. Enter your name, student number (e.g. `LU-2024-00123`), email, and password.
3. Once registered, log in to access the live terminal queue.

### 2. Driver Account
1. Click **I'm a Driver** > **Register**.
2. Enter your details, tricycle plate number (e.g. `LU-1234`), seating capacity (e.g. `6`), and choose the terminal.
3. Submit the registration request (drivers start as `pending` until approved).

### 3. Administrator Account
1. In the Supabase **Authentication** > **Users** dashboard, click **Add User** (e.g. `admin@lutrike.ph`).
2. In the Supabase **SQL Editor**, promote that account:
   ```sql
   select public.promote_to_admin('admin@lutrike.ph', 'System Administrator');
   ```
3. Sign in through the **Administrator sign in** portal in the web app to approve drivers and manage terminals.
