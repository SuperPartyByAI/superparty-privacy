# SuperParty Privacy Policy Site

This folder contains the static website for SuperParty's Privacy Policy and Data Deletion instructions, required for Google Play Console compliance.

## 📂 Files

- `index.html`: The main Privacy Policy.
- `deletion.html`: Instructions on how to request data deletion.
- `terms.html`: Terms of Service regarding call recording.

## 🚀 How to Publish (GitHub Pages)

1. **Create a New Repository** on GitHub (e.g., named `superparty-privacy`).
   - Make it **Public**.

2. **Push these files**:

   ```bash
   cd privacy-site
   git init
   git add .
   git commit -m "Initial commit for Privacy Policy"
   git branch -M main
   git remote add origin https://github.com/YOUR_USERNAME/superparty-privacy.git
   git push -u origin main
   ```

3. **Activate GitHub Pages**:
   - Go to Repo **Settings** > **Pages**.
   - Under **Build and deployment** > **Source**, select `Deploy from a branch`.
   - Select **Branch**: `main`, folder: `/ (root)`.
   - Click **Save**.

4. **Get Your Links**:
   After 1-2 minutes, your site will be live at:
   - **Privacy Policy URL**: `https://YOUR_USERNAME.github.io/superparty-privacy/`
   - **Data Deletion URL**: `https://YOUR_USERNAME.github.io/superparty-privacy/deletion.html`

## ✅ Where to use these links

| Google Platform    | Location                     | Link to Use                    |
| ------------------ | ---------------------------- | ------------------------------ |
| **Play Console**   | App Content > Privacy Policy | `index.html` link              |
| **Play Console**   | App Content > Data Safety    | Both links (Policy & Deletion) |
| **Google Cloud**   | OAuth Consent Screen         | `index.html` link              |
| **SuperParty App** | Settings > Privacy           | `index.html` link              |
