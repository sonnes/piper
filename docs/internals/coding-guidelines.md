---
title: "Coding Guidelines"
summary: "How Piper code is written: values, composition, threading, and the rules taken from NetNewsWire"
read_when:
  - Writing new Swift in this repository
  - Reviewing a change
  - Deciding between a subclass, a protocol, and a new type
---

# Coding Guidelines

This page is adapted from the NetNewsWire coding guidelines. See [Attribution](#attribution) for the source and for every place where Piper differs.

## Values

Piper's values, in order:

1. No data loss
2. No crashes
3. No other bugs
4. Fast performance
5. Developer productivity

These work together. The last one matters more than it looks. Work happens in small bursts, so anyone must be able to make progress in fifteen minutes.

## Problem Solving

Solve the problem. Do not solve less than the problem, and do not solve more than it. Do not generalize a solution before a second caller exists.

Work at the highest level that answers the problem. Do not work lower.

## Language

Write new code in Swift. Keep the Swift "pure" and avoid `@objc`, except where AppKit requires it.

Functions tend to be small. A one-line function is correct when its name explains the intent better than the line does.

Generics are allowed but rare. They raise the cost of reading the code.

Use assertions and preconditions. A force-unwrapped optional is a short form of a precondition failure, so use it rarely.

Extensions are allowed, including private extensions. Do not extend Foundation and AppKit so much that the result becomes a private dialect.

Mark a declaration `private` whenever that is possible. An API is what a caller needs, and nothing more.

Import `AppKit`, never `Cocoa`. Importing `Cocoa` also imports CoreData, which Piper does not use.

### Code Organization

Properties go at the top of a type. Functions follow. Extensions for protocol conformance follow the type. A private extension holds the private functions.

Use `// MARK:` to separate the sections.

## Composition

### No Subclasses

AppKit forces some subclasses, such as `NSView` and `NSViewController`. Everywhere else, no type is designed for subclassing.

This is a hard rule. Every Swift class is `final`.

### Protocols And Delegates

Protocols and delegates come before any other form of reuse. Implement protocol conformance in an extension.

If a delegate protocol and its delegator sit in one file, write the protocol first.

Default implementations in protocols are allowed, and they are slightly discouraged. A default implementation that acts like inheritance makes a reader jump between files.

### Small Objects

Objects with thousands of lines are not acceptable. Prefer several small objects, because a small problem is easier to hold in the head.

Do not split a large object at an arbitrary line. The split needs a reason. When no reason exists, the large object is the honest answer.

### Code Repetition

The no-subclasses rule produces some repetition. A small amount is correct, and it costs less than the alternative.

A large amount means the design is wrong. Break the problem into smaller objects instead.

## Model Objects

Model objects are plain objects. Piper uses no Core Data and no system that requires subclassing.

Immutable structs come first. A small amount of extra work to reach one is worth it. When that fails, use a mutable struct or a reference type, whichever the case needs.

## Modules

Piper is layered into modules under `Sources/Modules`, with the application target above them. Each module has one reason to exist.

Dependencies between modules stay as few as possible. `PiperCore`, `PiperTree`, and `CapturesDatabase` add no dependency on another Piper module. They sit at the bottom, which keeps them reusable and keeps the build graph simple.

Do not fight the system frameworks, and do not hide them behind a wrapper.

## User Interface

Use stock elements. Custom work invites bugs and future churn, so keep it to the minimum. Piper is built for the long term.

`NSWindowController`, `NSSplitViewController`, `NSOutlineView`, and `NSToolbar` own the window chrome, the panes, and the sidebar. They give state restoration, keyboard handling, and responder chain behavior at no cost.

Each pane is an `NSViewController`. Its `view` is an `NSHostingView` around one SwiftUI view.

Panes never call each other. A pane reports upward through a delegate protocol, and `MainWindowController` decides what happens next.

Put sizes, colors, and other parameters in `AppDefaults` and `PiperTheme`. Do not write a literal color in a view.

Use nil-targeted actions and the responder chain where they fit.

## State Changes

Key-Value Observing is banned. KVO is where the crashing bugs live. The only exception is an Apple API that requires it, which is rare.

`NSArrayController` and Cocoa bindings are never used.

Inside a module, state changes travel through Swift `Observation` and through `didSet`.

Across modules, state changes travel through `NotificationCenter`. Declare every notification name in `AppNotifications.swift`.

Post every notification on the main queue.

## Threading

Everything runs on the main thread.

The exceptions are tasks that isolate perfectly: a folder scan, a Markdown parse, a database read. Those run on a serial `DispatchQueue` or in a detached `Task`.

Those tasks run without locks. Piper uses almost no locks.

When a background task finishes, it calls back on the main queue. A private case can do otherwise, and then the code says so in a comment.

If this policy produces a design that blocks the main thread, rewrite the design.

## Cleanliness

Do not commit code that produces a compiler error. Do not commit code that produces a compiler warning.

Console spew is not allowed. Remove every print statement before you commit.

## Profiling

Use Instruments to find leaks and to profile. Instruments finds where the problem is, which is often not where it seems to be.

Look for memory leaks before every release.

## Testing

Write unit tests, above all in the lower modules, and above all when you correct a bug.

Test coverage is never enough. Piper writes no tests for the user interface. Everywhere else, more tests are correct.

## Version Control

Start every commit message with a present-tense verb.

## Formatting

Piper indents with four spaces.

## Last Thing

Do not show off. Code that looks like kindergarten code is good code.

Points go to whoever does not try to collect points.

## Attribution

This page is adapted from `Technotes/CodingGuidelines.md` in NetNewsWire, by Brent Simmons and the NetNewsWire contributors, retrieved on 2026-09-14.

- Source: <https://github.com/Ranchero-Software/NetNewsWire/blob/main/Technotes/CodingGuidelines.md>
- Copyright (c) 2002-2025 Brent Simmons
- License: MIT, reproduced at [Licenses/NetNewsWire.txt](../../Licenses/NetNewsWire.txt)

NetNewsWire does not endorse Piper, and it has no connection to this project.

### Where Piper Differs

| Rule in NetNewsWire | Rule in Piper | Reason |
| --- | --- | --- |
| Use AppKit and `.xib` files on macOS. Avoid SwiftUI. | AppKit owns the window chrome. SwiftUI draws the content of each pane. | The Piper target is about 6,000 lines of Swift, most of it SwiftUI. A full AppKit rewrite costs weeks and changes nothing that a reader sees. |
| Use Auto Layout in `.xib` files, not in code. | No `.xib` files. SwiftUI lays out the pane content. Split view items set minimum thickness in code. | This follows from the rule above. |
| Prefer storyboards to xibs. | Neither. Window controllers build their split view controllers in code. | Swift Package Manager builds Piper. It has no Interface Builder step. |
| `NotificationCenter` and `didSet` carry every state change. | `Observation` carries state inside a module. `NotificationCenter` carries it across modules. | `Observation` did not exist when the original rule was written. It gives the same result as `didSet` without the manual wiring, and it is not KVO. |
| Indent with tabs. | Indent with four spaces. | Every existing Piper source file uses four spaces. |
| Write new code in Swift 5. | Write new code in Swift, with no version pinned in the guidance. | The Swift version belongs in `Package.swift`, not in prose that goes stale. |
| Frameworks live in `Modules/` beside an Xcode project. | Modules live in `Sources/Modules` as Swift Package Manager targets. | Piper has no Xcode project. |

Every other rule on this page comes from the original, restated in shorter sentences.
