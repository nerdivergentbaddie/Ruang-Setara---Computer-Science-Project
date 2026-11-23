# Ruang Setara — community platform starter (v3)

Responsive bilingual website about women's rights, peer support, public place observations and route planning. This project has a static frontend and a Supabase backend schema. It is designed to be hosted on GitHub Pages and use Supabase for shared accounts/data.

## What works after Supabase is configured

- **Real account registration and sign-in:** Supabase Auth (email + password). One permanent account can be used across devices.
- **Editable profile display name:** users can update their display name after sign-in.
- **Per-activity anonymous identity:** each community post, reply and place observation can be published under the account display name or `Anonymous member`. The account remains signed in either way. Story Space has its own anonymous/private identity option.
- **Community feed:** public posts and threaded replies, newest first.
- **Place observations:** public observation feed, replies and optional JPG/PNG/WebP photo upload (5 MB max).
- **Story Space:** private support requests, never shown in public feeds. The owner and verified helpers can read the story. Verified helpers can reply privately; the owner can read the private response and continue the thread.
- **Role applications:** community member, volunteer applicant, or professional applicant. Applicants remain ordinary members until an admin verifies them and explicitly grants the role.
- **Professional/volunteer inbox:** verified helpers can see private requests. This starter has a shared helper inbox, not case assignment or staffing/availability management.
- **Plan your journey:** Leaflet map with road route geometry from OpenStreetMap/OSRM. Route estimates are not a safety rating or live traffic.
- **Resources:** links to SAPA 129, Komnas Perempuan, LBH APIK and other support resources.

## Important: GitHub Pages is not the backend

GitHub Pages only hosts the website files. Supabase provides authentication, database, Row Level Security (RLS), and photo storage. Without Supabase configuration, the app deliberately blocks shared posts and sensitive stories instead of pretending that local browser storage is public.

## Setup

1. Create a project at [Supabase](https://supabase.com/).
2. In Supabase **SQL Editor**, run the complete `supabase/schema.sql` file.
3. In Supabase **Authentication → URL Configuration**, set your GitHub Pages URL as the Site URL and add it to Redirect URLs. Example: `https://YOUR-USERNAME.github.io/YOUR-REPO/`.
4. In `index.html`, find `window.RS_CONFIG` near the bottom and replace the empty values:

   ```js
   window.RS_CONFIG = {
     supabaseUrl: "https://YOUR-PROJECT.supabase.co",
     supabaseAnonKey: "YOUR_SUPABASE_ANON_PUBLIC_KEY"
   };
   ```

   Use only the Supabase **anon/public** key. Never place `service_role`, a secret key, or database password in browser code or GitHub.
5. Commit `index.html`, `README.md`, and `supabase/schema.sql` to your GitHub repository. Enable GitHub Pages under **Settings → Pages**.
6. Register a test account. If email confirmation is enabled, confirm the email before signing in.
7. Test using two separate accounts or browser profiles: publish a named post, an anonymous post, replies, an observation with a test photo, and a private story. Confirm public feeds never show a story and a regular account cannot open the helper inbox.

## How anonymous identity works

- Every user has one real Supabase Auth account and a private account UUID.
- Each public post, reply and observation independently stores `is_anonymous` plus a server-stamped display label. The database trigger ignores any client-supplied label and stamps either the profile display name or `Anonymous member`.
- Public feed database grants omit the account UUID (`author_id`) from readable columns. Public visitors see only the selected display label and content.
- Story Space is separate: if anonymous is selected, the database stores a null display name on the story. The story is accessible only to its owner and verified helpers.
- Anonymous means the display identity is hidden in the app. It is not end-to-end anonymity against the platform/database administrator, legal process, compromised devices, or information the author includes in their own text/photo.
- Changing a profile name affects future posts; older public posts keep the display label that was used when they were published.

## Approving professionals and volunteers

Selecting a role during registration only creates an application with `professional_status='pending'`. It does not grant privileged access. Verify identity, qualifications, references, safeguarding training and scope of practice outside the website. Then, from the Supabase SQL Editor, use the applicant's Auth user UUID:

```sql
-- Verify a professional applicant
update public.profiles
set role='professional', professional_status='verified'
where id='AUTH_USER_UUID';

-- Or verify a volunteer applicant
update public.profiles
set role='volunteer', professional_status='verified'
where id='AUTH_USER_UUID';
```

To reject an application, set `professional_status='rejected'` and leave `role='community'`. Do not promote anyone based only on their signup selection.

## Privacy and safety — read before launch

This is a functional starter, **not a production-ready survivor-support service**. Before collecting real stories or opening public registration:

- Commission an independent security/privacy review and threat model. Add a named data controller, privacy notice, retention/deletion policy, incident response plan and public contact channel.
- The current helper inbox is shared among all verified helpers. Add case assignment, least-privilege access, audit logs, confidentiality agreements, staff training, escalation rules and safe deletion/export workflow before handling real cases.
- Story messages and story bodies are stored in Supabase and are not end-to-end encrypted. Never promise absolute confidentiality. Consider client-side encryption and professional security review if storing highly sensitive details.
- Add robust moderation, report/block tools, rate limits, spam prevention and content review before opening public feeds to the public.
- Public observation photos are publicly accessible. Do not upload faces, license plates, survivors, private addresses, shelters, or identifying information. Do not use the public photo bucket for evidence, identity documents or private images.
- Public posts and replies are public. Users should not identify third parties or publish unverified allegations as fact.
- Verify all external support links, emergency contacts, coverage and operating hours periodically. The site is not an emergency response, legal or medical service.
- Route data does not assess harassment, crime, lighting or real-time hazards. Public Nominatim/OSRM/OSM endpoints have fair-use limits and no uptime guarantee; use a compliant hosted provider at scale.
- Test keyboard navigation, screen readers, captions, contrast, mobile use and disability access with disabled users before launch.

## Troubleshooting

- **Sign-up succeeds but no session:** email confirmation may be enabled. Confirm the email and then sign in.
- **Permission denied / missing relation:** rerun `supabase/schema.sql` in SQL Editor and check the Supabase project URL/key.
- **Profile not created:** confirm the `on_auth_user_created` trigger exists and inspect Supabase Auth logs.
- **Photo upload fails:** confirm the `place-photos` bucket and storage policies were created by the schema.
- **Professional inbox hidden:** the account must be manually assigned `role='professional'` or `role='volunteer'` and `professional_status='verified'`.
- **Anonymous name display:** the database triggers stamp public identity. If you edited the SQL manually, ensure all four `stamp_*_identity` triggers exist.
