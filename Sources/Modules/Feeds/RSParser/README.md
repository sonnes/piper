# RSParser

This folder is a copy of the RSParser module and two files of the FeedFinder module of NetNewsWire, at commit `7908c801bf7c97fa7cca9ef78cf51b33fb853e6a`. The license is MIT. See `Licenses/NetNewsWire.txt`.

Piper changes these parts of the copy:

- Indents use four spaces.
- `String+FeedURL.swift` replaces the RSCore and RSWeb helpers.
- `ParsedItem` does not render Markdown.
- `FeedSpecifier` has no special cases for known sites.
- The HTML image parsers are not in the copy.

The tests are in `Tests/FeedsTests`.
