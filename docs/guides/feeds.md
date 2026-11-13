---
title: "Read Feeds"
summary: "Subscribe to RSS, Atom, and JSON feeds, import NetNewsWire subscriptions, read articles in the main window, and find feeds from browser history with Discover"
read_when:
  - Adding a feed or importing an OPML file
  - Moving from NetNewsWire
  - Reading, starring, or keeping an article
  - Finding feeds on the sites of your history
  - Blocking a site from Discover
  - Giving Piper access to Safari history
---

# Read Feeds

Piper reads RSS, Atom, RSS-in-JSON, and JSON Feed. The Feeds group of the sidebar holds these rows:

| Row | Content |
| --- | --- |
| Discover | The sites of your recent browser history, and the feed of each site |
| All Unread | The unread articles of every feed |
| Starred | The articles that you starred |
| A feed | The articles of that feed |

Each row shows a count of unread articles. Starred shows a count of starred articles.

A feed shows the icon of its site. Piper gets the icon from the home page of the site. Until Piper finds an icon, the feed shows the first letter of its title. Discover and the article rows show the same icons.

## Add A Feed

1. Select the + button in the header of the Feeds group. You can also choose Add Feed from the + menu of the toolbar.
2. Type the address of a site or of a feed.
3. Select Find Feeds.
4. If the site has more than one feed, choose one.
5. Select Subscribe.

## Import Subscriptions

1. Open Add Feed.
2. Open the Import menu.
3. To import the subscriptions of NetNewsWire, choose Import from NetNewsWire.
4. To import another OPML file, choose Import OPML File, and select the file.

Piper reads the On My Mac account of NetNewsWire. The import adds each feed one time and skips the feeds that Piper has. The import does not copy articles, read marks, or stars. Piper does not read NetNewsWire after the import.

If Piper cannot read the NetNewsWire file, give Piper Full Disk Access. You can also export the subscriptions from NetNewsWire as an OPML file, and import that file.

## Read Articles

Select a row in the Feeds group. The list pane shows the articles, the newest first. Select an article to read it in the detail pane. The detail pane is the same reader as a link in Inbox. The Reader tab shows the article as clean text, and the Web tab shows the original page.

When you select an article, Piper marks it as read. The article stays in the list until you select another row.

| Key | Action |
| --- | --- |
| Space | Open the next unread article |
| R | Mark the article as read or unread |
| S | Star the article, or remove the star |
| B | Open the article in the browser |
| I | Keep the article in Inbox |
| Command-K | Mark all articles in the list as read |

The window toolbar has Keep in Inbox, Star, and Mark as Read over the detail pane. Right-click an article for the same actions, Open in Browser, and Copy Link.

Keep saves the article to Inbox as a link capture. The source of the capture is the title of the feed. After Keep, the detail pane also shows the Notes tab. A highlight or a note on a feed article also keeps the article, because a note needs a capture.

## Refresh

Piper refreshes each feed every 30 minutes, while Piper is open. Piper refreshes up to 4 feeds at the same time. To refresh all feeds now, select the refresh button in the header of the list.

If a feed fails, its row shows a warning icon. Move the pointer over the row to read the error. Piper tries again after 30 minutes, and again after 30 more minutes. Then the waits are 2 hours, 8 hours, and 24 hours.

Piper removes a read article 30 days after it arrives. Piper keeps each starred article.

## Manage A Feed

Right-click a feed in the sidebar:

| Item | Action |
| --- | --- |
| Mark All as Read | Mark each article of the feed as read |
| Copy Feed Address | Copy the address of the feed |
| Unsubscribe | Remove the feed and its articles |

## Discover

Discover finds the sites that you visit and looks for a feed on each site. Discover uses no AI.

1. Piper reads the last 14 days of browser history on this Mac.
2. Piper ranks the sites by visits. A recent visit counts more than an old visit.
3. Piper loads the home page of each site and looks for a feed.

Each site with a feed shows Subscribe and Ignore. The sites with no feed are in a folded section at the end. Each of these sites shows Open and Ignore. Ignore hides the site from later scans.

Piper scans when you open Discover and the last scan is older than one day. To scan now, select Scan Again.

The history does not leave your Mac. The scan sends one request to the home page of each site, and more requests to the feeds that the page names.

## Choose The History Sources

Open Settings > Feeds.

- To stop Discover from reading a browser, turn off its switch.
- If a source shows Open Privacy Settings, Piper needs Full Disk Access to read it. Safari needs this access.
- To block a site, add its host to Blocked Sites. Type one host on each line. A block also covers each subdomain.

Piper always blocks private addresses.
