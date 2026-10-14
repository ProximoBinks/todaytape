# Connect Todaytape to your Google Calendar

Todaytape doesn't come with a Google login of its own. You create a small, private Google client for yourself, once. Your calendar then goes straight from Google to your Mac, and nobody else (including the Todaytape developer) is involved.

It takes about 5 minutes. You need a Google account and a browser. It's free.

The steps below match the **Set up Todaytape** window, which opens when you first run the app. Each step there has buttons that open the right Google page.

---

## Step 1: Prepare a Google Cloud project

1. **Create a project.** Open [Create a project](https://console.cloud.google.com/projectcreate), give it any name (for example `Todaytape`) and click **Create**. Make sure the new project is selected in the bar at the top.
2. **Turn on the Calendar API.** Open [Enable the Google Calendar API](https://console.cloud.google.com/flows/enableapi?apiid=calendar-json.googleapis.com) and click **Enable**.
3. **Set up the sign-in screen.** Open [Google Auth Platform → Branding](https://console.cloud.google.com/auth/branding) and click **Get started**:
   - **App name:** `Todaytape` (only you will see it). **User support email:** your email. **Next.**
   - **Audience:** choose **External**. **Next.**
   - **Contact information:** your email. **Next.**
   - Agree to the Google API Services User Data Policy, then **Continue** and **Create**.
4. **Add yourself as a test user.** Open [Audience](https://console.cloud.google.com/auth/audience). Under **Test users**, click **Add users**, enter the Gmail address whose calendar you want to see, and **Save**.

Leave **Publishing status** on **Testing**. Don't publish the app; you're its only user.

> **Using a Google Workspace (work or school) account?** If you created the project inside your organisation, you can choose **Internal** instead of External. Internal skips the test-user list and the 7-day sign-in limit. Your administrator may need to allow it.

## Step 2: Add your Desktop client

1. Open [Google Auth Platform → Clients](https://console.cloud.google.com/auth/clients) and click **Create client**.
2. **Application type:** **Desktop app**. Name it anything (for example `Todaytape on my Mac`). Click **Create**.
3. In the dialog that appears, click **Download JSON**. Google only shows the client secret here, so download it before you close the dialog.
4. In Todaytape, click **Import client JSON…** and choose the file you downloaded (it's named `client_secret_….json` and is usually in Downloads).

Prefer to paste? Click **Paste instead** and copy the **Client ID** and **Client secret** from the same dialog.

## Step 3: Connect Google Calendar

1. Click **Connect Google Calendar**. Your browser opens Google's sign-in.
2. Choose the account you added as a test user.
3. Google says **"Google hasn't verified this app."** That's expected: it's your own app, and only you can use it. Click **Continue**.
4. Allow Todaytape to **see your calendars**, then **Continue**.
5. The browser says Todaytape is connected. Close the tab.

The tape appears on the right edge of your screen. Pick which calendars to show and their colours in Settings.

---

## Good to know

**Read-only.** Todaytape asks for the `calendar.readonly` permission. It can't create, change or delete events.

**Where your data lives.** Everything stays in `~/.todaytape` on your Mac, readable only by your user account:

| File | Contents |
|---|---|
| `credentials.json` | Your client ID and secret |
| `tokens.json` | The sign-in Google gave Todaytape |
| `settings.json` | Calendars shown, colours, appearance |

Disconnect in Settings to sign out and ask Google to revoke access. You can also remove access at any time from [your Google Account's third-party access page](https://myaccount.google.com/connections).

**You'll reconnect about once a week.** Google ends sign-ins for apps in Testing after 7 days. When that happens, Todaytape shows **Set up** on the tape; open Settings and click **Connect Google Calendar** again. Your client and settings are kept. Only a verified, published app avoids this, and that verification is meant for apps used by the public, not personal clients.

## Troubleshooting

| You see | Fix |
|---|---|
| **Access blocked: Todaytape has not completed the Google verification process** | Your Gmail isn't a test user yet. Add it under [Audience](https://console.cloud.google.com/auth/audience) (step 1.4), then connect again. |
| **Error 400: redirect_uri_mismatch** or **This is a Web application client** | You created a Web application client. Create a **Desktop app** client instead (step 2). |
| **Google rejected the client ID or secret** | The client was deleted, or the secret was reset. Download the JSON again (or create a new Desktop client) and import it. |
| **The Google Calendar API is off for your project** | Enable it (step 1.2), wait a minute, then click **Refresh**. |
| **Your Google sign-in expired** | The 7-day Testing limit. Click **Connect Google Calendar**. |
| **"Todaytape can't be opened"** when launching | See [Opening an unsigned app](../README.md#opening-todaytape-for-the-first-time) in the README. |
| The browser never comes back | Click **Cancel** in Todaytape, then **Connect** again. Sign-in times out after 5 minutes. |

Still stuck? [Open an issue](https://github.com/ProximoBinks/todaytape/issues) with the message you see. Don't include your client secret.
