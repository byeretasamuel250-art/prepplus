# prep+ — setup guide

A UCE/UACE exam-prep quiz app: students practice past-paper questions
by topic, by year, or against the clock, and see exactly which topics
they're weak in. Free sample subjects are open to everyone; full access
is a UGX 3,000/month subscription, same manual-approval model as new+.

**Files in this folder**
- `index.html` — the student app
- `admin.html` — the admin dashboard (where you add subjects, topics, and questions — separate page, never linked from the student app)
- `config.js` — where you paste your Supabase keys (only file you must edit)
- `style.css`, `shared.js` — shared design and logic, don't need editing
- `schema.sql` — creates all the database tables, security rules, and helper functions

This uses the exact same security model as new+: a student can only
ever see their own quiz history, question content is gated by
subscription at the database level (not just hidden in the app), and
admin actions require a real login — nothing is left open by trusting
the browser.

---

## Step 1 — Create a Supabase project

You can reuse the **same** Supabase project you made for new+, or make
a fresh one for prep+ — both are fine, the tables won't conflict.

If starting fresh: go to supabase.com → **New project** → name it,
set a database password (save it), pick a region, create it, wait ~2 minutes.

## Step 2 — Build the database

1. **SQL Editor** → **New query**.
2. Copy all of `schema.sql`, paste it in, click **Run**.
3. You should see "Success. No rows returned."

## Step 3 — Connect the app

1. **Project Settings → API** → copy the **Project URL** and **anon public** key.
2. Paste both into `config.js`:
   ```js
   const SUPABASE_URL = "https://xxxxxxxx.supabase.co";
   const SUPABASE_ANON_KEY = "eyJhbGciOi...";
   ```

## Step 4 — Turn on Anonymous Sign-ins

**Authentication → Sign In / Providers → Anonymous Sign-ins → on.**
This is what lets phone + PIN work without OTP or email, same as new+.
*(Already on if you set this up for new+ in the same project — skip it.)*

## Step 5 — Create your admin login

1. **Authentication → Users → Add user** — enter your email + password, leave Auto Confirm on.
2. **SQL Editor** → run (with your real email):
   ```sql
   insert into admin_allowlist (email) values ('you@example.com');
   ```
   *(If reusing the new+ project and you already added yourself there, run this line anyway — prep+ has its own separate `admin_allowlist` table.)*
3. Open `admin.html` and log in.

## Step 6 — Add your first subject and content

1. In `admin.html`, go to the **Content** tab.
2. **Add a subject** — name it, pick UCE or UACE, and tick **Free** for at least one subject so you have something to test without needing to subscribe.
3. Click the subject you just added.

From here you have two ways to add content — use either or both:

**Fastest: upload scanned papers as-is.** Scan or photograph a past paper, then under "Upload a scanned past paper" give it a title (e.g. "Biology Paper 1"), optionally a year and paper number, choose the file (image or PDF), and click **Upload**. Students see it in the "Past papers library" the moment they open the subject — no retyping needed. This is the quickest path to real content.

**Slower but interactive: type questions in for the quiz.** Add a topic or two, then use "Add a question" to type out the question, all 4 options, mark the correct one, and optionally an explanation. This powers the auto-graded practice modes (topic practice, full paper, timed exam) with instant feedback and topic-by-topic scoring — worth doing for subjects you want students to actively drill, when you have time to type them in.

## Step 7 — Test locally

Same as new+:
```
python3 -m http.server 8080
```
Visit `http://localhost:8080`, register a test student account, and you should see your free subject with the questions you just added. Try all three modes — topic practice, full paper (needs a year set on your questions), and timed exam.

## Step 8 — Publish

Same as new+ — drag the folder onto **Netlify**, or push to **GitHub Pages**, or **Vercel**. Student link is the root URL; keep `/admin.html` private.

---

## Day to day

**Adding new content:** every past paper you get, log into `admin.html` → open the subject → scan or photograph it and upload it directly (fastest), or type it in as quiz questions if you want that subject to have interactive practice too. This is the main ongoing work of running the app.

**Approving payments:** identical to new+ — Payment requests tab, check your mobile money statement, Approve.

**A student's experience:** register → sees free subjects immediately, locked subjects show a subscribe prompt → picks a subject → browse the **past papers library** to view uploaded originals, or use **topic practice**, **full paper by year**, or a **30-minute timed exam** for subjects with quiz questions → instant feedback per question → a score screen broken down by topic → history saved to their profile. Uploaded papers stay locked behind the same subscription check as everything else — a student can't reach the file just by knowing its link.

## If you see a white screen

Same causes as new+: `config.js` not filled in, Anonymous Sign-ins off, or no internet (the Supabase library loads from a CDN) — the app shows a plain-language error for each instead of a blank page. Check the browser console (F12) for anything else.
