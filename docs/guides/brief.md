---
title: "Read The Daily Brief"
summary: "Build a brief from browser history, NetNewsWire, and Hacker News, highlight it, limit what Claude receives, and turn on morning builds"
read_when:
  - Building the first brief
  - Blocking a site from a brief
  - Giving Piper access to Safari or NetNewsWire
  - Signing in to a site for a brief
  - Highlighting a brief or opening its links
---

# Read The Daily Brief

The Brief page is the first page of the main window. Press Command-0 to open it. Each brief uses the last 14 days of browser history, recent NetNewsWire articles, the popular Hacker News submissions of the last day, and the pages of up to 8 sites.

A brief uses Claude Code. Sign in to Claude Code before you build a brief.

## Build The First Brief

1. Press Command-0.
2. Read the list under What Claude receives.
3. To remove a site, select Never Send.
4. Select Build Brief.

A build takes a few minutes. After the first brief, Piper asks one time if it must build a brief each morning. A morning build runs one time each day, between 5:00 and noon, while Piper is open. To change this choice, open Settings > Brief.

Select the arrows at the top of the page to read an earlier brief. Select Rebuild to replace the brief of today.

## Repeated Links

A brief does not use a link that a brief of an earlier day holds. This rule applies to NetNewsWire articles, Hacker News stories, and the links of each page. Piper also gives Claude the labels of the removed page links, and tells Claude not to write about these items. If you rebuild the brief of today, that brief can use the links of the earlier brief of today again.

Piper reads the earlier links from the saved briefs. Links must be the same to match. Only a last slash and a fragment can differ, so one story at two addresses can appear again.

## Highlight A Brief

A brief has the same selection bar as the Reader tab of an article. Select text to show the bar.

- To highlight the text, select a color.
- To write a note, select Note. Type the note, then press Return.
- To ask about the text, select Ask, Explain, or Define.

The first highlight of a brief adds a note named "Brief for" and the date to Inbox. Each highlight of that brief shows under this note. When you delete this note, Piper also deletes its highlights.

If you rebuild the brief of today, a highlight stays only if the new brief holds its quote. If the quote is gone, the note stays in Inbox and the brief shows no mark.

## Open A Link

Select a link in a brief. Piper adds the link to Reading and opens the page in the Web tab. Use the Reader tab of that link to highlight the article. To go back, select Brief in the sidebar. The brief opens at the place where you stopped.

## Data That Leaves Your Mac

Piper sends this data to Anthropic through Claude Code:

- The top 30 sites, with visit counts and up to 5 page titles for each site. Piper does not send full URLs.
- The text and the links of up to 8 pages.
- Up to 40 unread or starred NetNewsWire articles.
- Up to 30 Hacker News stories, with their titles, links, points, and comment counts.

Piper gets the Hacker News stories from the public API at `hn.algolia.com`. A story must be less than one day old and must have 50 points or more. The request holds no data from your Mac, other than your network address.

CAUTION: Do not sign in to a site in Piper if its private pages must stay on your Mac. Piper sends the text of each page that it loads, and that text can appear in the brief.

Piper does not change your history or your NetNewsWire read marks. It deletes each temporary copy after the read.

## Choose The Sources

Open Settings > Brief. Each browser profile, each NetNewsWire account, and Hacker News has a switch.

If a source shows Open Privacy Settings, macOS refused access to it. Safari always needs this access, and NetNewsWire can need it.

1. Select Open Privacy Settings.
2. Turn on Full Disk Access for Piper.
3. Restart Piper.

CAUTION: Agent sessions that Piper starts can get the same access. Do not give this access if you run agents that you do not trust.

## Block A Site

Open Settings > Brief, and enter one host on each line under Blocked Sites. A block also covers each subdomain. Piper always blocks private addresses and local names. A company site with a public name needs its own line.

## Sign In To A Site

Piper does not use the sign-ins of your browsers. A site that needs a sign-in gives only its public page.

1. Select Sites at the top of the page, or read the list of the first brief.
2. Select Sign In next to the site.
3. Sign in, then select Done.

The Web tab uses the same sign-ins.
