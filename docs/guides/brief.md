---
title: "Read The Daily Brief"
summary: "Build a brief of up to 8 links from browser history, NetNewsWire, and Hacker News, read the picks in Inbox, limit what Claude receives, and turn on morning builds"
read_when:
  - Building the first brief
  - Reading, keeping, or skipping a pick
  - Blocking a site from a brief
  - Giving Piper access to Safari or NetNewsWire
  - Signing in to a site for a brief
---

# Read The Daily Brief

A brief is a list of up to 8 links to read today. Each link is a pick. The picks show in a Brief group at the top of Inbox, in the main window and in the capture panel. Each pick shows its title on one line. The second line shows its site and one sentence from Claude about the reason for the pick. If the sentence is too long for the line, move the pointer over it to read all of it.

A brief uses the last 14 days of browser history, recent NetNewsWire articles, the popular Hacker News stories of the last day, and the links on the home pages of up to 8 sites.

A brief uses Claude Code. Sign in to Claude Code before you build a brief.

## Build The First Brief

1. Open Settings > Brief.
2. Select Show Sites, and read the list under What Claude receives.
3. To remove a site, select Never Send.
4. Select Build Brief.

You can also select Build Brief in the Brief group of Inbox. The group shows this button when no brief of today exists.

A build takes a few minutes. While it runs, the Brief group shows its progress. After the first brief, the group asks one time if Piper must build a brief each morning. A morning build runs one time each day, between 5:00 and noon, while Piper is open. To change this choice, open Settings > Brief.

If a build fails, the group shows the reason and Try Again.

## Read The Picks

| Action | Result |
| --- | --- |
| Select the title | Piper saves the link to Inbox and opens it in the Web tab. The pick leaves the group. |
| Select Keep | Piper saves the link to Inbox. The pick leaves the group. |
| Select Skip | The pick leaves the group. Piper does not save the link. |
| Select the circle | Piper marks the pick as read. The pick leaves the group. |

A saved pick is a link capture with the source "Brief". The header of the group counts the picks that are left. To hide the picks, select the arrow in the header. When no pick is left and the brief of today exists, the group goes away.

## How Piper Ranks The Links

Piper ranks the links before Claude sees them. The rank uses the decay formula of Hacker News. A link gets points, and the points decrease with the age of the link:

| Link | Points | Age |
| --- | --- | --- |
| A Hacker News story | The points of the story | The time since the post |
| A starred NetNewsWire article | 100 | The time since the article was published. If the article has no date, 1 day. |
| An unread NetNewsWire article | 40 | The same as a starred article |
| A link on a home page | 30 | The time since the last brief, at most 1 day |

A site that you visit often adds points to each link on that site. A visit counts more when it is recent. Piper sends the best 25 links to Claude, and Claude picks up to 8 of them.

## Repeated Links

A brief does not use a link that a brief of an earlier day holds. This rule applies to NetNewsWire articles, Hacker News stories, and the links on each page. If you build the brief of today again, that brief can use the links of the earlier brief of today.

Piper reads the earlier links from the saved briefs. Links must be the same to match. Only a last slash and a fragment can differ, so one story at two addresses can appear again.

## Data That Leaves Your Mac

Piper sends this data to Anthropic through Claude Code:

- The top 30 sites, with up to 5 page titles for each site. Piper does not send full URLs.
- The titles and the sites of up to 25 links. A Hacker News link also has its points and its comment count. A NetNewsWire link also has the start of its summary.

Piper does not send the URLs of the links. Claude replies with the numbers of the links, and Piper takes the title and the URL of each pick from its own list.

Piper gets the Hacker News stories from the public API at `hn.algolia.com`. A story must be less than one day old and must have 50 points or more. The request holds no data from your Mac, other than your network address.

CAUTION: Do not sign in to a site in Piper if its private pages must stay on your Mac. Piper sends the link titles of each page that it loads, and these titles can appear in the brief.

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

1. Open Settings > Brief, and select Show Sites.
2. Select Sign In next to the site.
3. Sign in, then select Done.

The Web tab uses the same sign-ins.
