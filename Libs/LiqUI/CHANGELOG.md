# Changelog

## v1.3.0 - 2026-08-12

- Updated window and table creation so hosts pass a unique name and optional saved layout storage directly.
- Updated the debug log to one shared window with an addon dropdown instead of a separate log window per host.
- Fixed close and settings titlebar icons when LiqUI is embedded under a host addon. Thank you @MOSS099, @benhilty, and @ynazar1.
- Updated TOC number to support patch 12.1.

## v1.2.0 - 2026-07-22

- Fixed window position after drag, reload, column resize, and scale changes so the top-left corner stays on the same screen pixel from 80% to 200% scale.

## v1.1.0 - 2026-06-21

- Removed optional sidebar from the reusable window layout.
- Updated window sizing so the width you set matches the main content area only.
- Added a unified window overlay for empty states, loading text, and optional progress.
- Updated window overlay to replace the body while shown so resized content does not paint outside the window.
- Updated window position saving to use top-left anchors so resizing no longer shifts the window on screen. Existing saved positions from older versions are ignored until you move the window again.
- Updated default window placement to 30 pixels from the top-left for main windows and 300 pixels for other windows.
- Fixed window clamping so windows can be dragged partially off the left, right, and bottom screen edges while the top edge stays on screen.

## v1.0.0 - 2026-06-20

- Added reusable window layout with titlebar, resize, optional sidebar, progress overlay, and empty-state placeholder text.
- Added per-window scale, background color, border, and screen position persistence.
- Added window chrome controls on the titlebar options menu.
- Added data tables with sticky sortable headers, scrolling, icons, and multi-line text cells.
- Added optional debug log window with persisted scroll position.
- Added independent saved layout storage for each embedding addon.
- Fixed scrollbars appearing when scroll content nearly fits the visible area.
