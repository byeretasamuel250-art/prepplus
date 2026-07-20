// ============================================================
// prep+ shared helpers
// ============================================================

function initSupabase() {
  const root = document.getElementById("app");
  try {
    if (typeof window.supabase === "undefined") {
      throw new Error("Supabase library did not load. Check your internet connection and refresh.");
    }
    if (!SUPABASE_URL || SUPABASE_URL.includes("PASTE_") || !SUPABASE_ANON_KEY || SUPABASE_ANON_KEY.includes("PASTE_")) {
      throw new Error("config.js is not set up yet. Open config.js and paste in your Supabase Project URL and anon key (see SETUP_GUIDE.md, step 3).");
    }
    return window.supabase.createClient(SUPABASE_URL, SUPABASE_ANON_KEY);
  } catch (err) {
    root.innerHTML = `
      <div class="brand">prep<span class="plus">+</span></div>
      <div class="error-banner"><strong>Couldn't start the app.</strong><br>${err.message}</div>`;
    throw err;
  }
}

async function ensureSession(sb) {
  const { data: { session } } = await sb.auth.getSession();
  if (session) return session;
  const { data, error } = await sb.auth.signInAnonymously();
  if (error) {
    throw new Error(
      "Couldn't start a session (" + error.message + "). " +
      "Make sure Anonymous Sign-ins are enabled in Supabase " +
      "(Authentication → Sign In / Providers), see SETUP_GUIDE.md step 4."
    );
  }
  return data.session;
}

function safeRender(fn) {
  return async (...args) => {
    try {
      await fn(...args);
    } catch (err) {
      console.error(err);
      const root = document.getElementById("app");
      root.innerHTML += `<div class="error-banner"><strong>Something went wrong.</strong><br>${err.message || err}</div>`;
    }
  };
}

function initials(name) {
  if (!name) return "?";
  return name.trim().split(/\s+/).slice(0, 2).map(w => w[0].toUpperCase()).join("");
}

function timeAgo(iso) {
  const d = new Date(iso);
  const diffMs = Date.now() - d.getTime();
  const mins = Math.floor(diffMs / 60000);
  if (mins < 1) return "just now";
  if (mins < 60) return `${mins}m ago`;
  const hrs = Math.floor(mins / 60);
  if (hrs < 24) return `${hrs}h ago`;
  const days = Math.floor(hrs / 24);
  return `${days}d ago`;
}

function escapeHtml(str) {
  const d = document.createElement("div");
  d.textContent = str ?? "";
  return d.innerHTML;
}

function friendlyError(error) {
  const msg = error?.message || String(error);
  if (msg.includes("phone_taken")) return "That phone number is already registered. Try logging in instead.";
  if (msg.includes("invalid_credentials")) return "Wrong phone number or PIN.";
  if (msg.includes("no active session")) return "Your session expired — please refresh the page and try again.";
  return msg;
}
