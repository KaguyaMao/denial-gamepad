# Gamepad touch desktop

`DENIAL_SHELL_PROFILE=gamepad` selects the shared desktop scene with touch
policy. It reuses the desktop plugin's windows, workspaces and overview, and
adds touch-first admission and resize behavior in the compositor.

## Layout model

- The compositor's Dwindle layout owns native window placement. Flutter mirrors
  placements and publishes input routing.
- Every application opens as a tile. While the active workspace still has free
  space, a new application tiles in beside the existing ones and the layout
  assigns each a reasonable share.
- Once the workspace is full, the next application replaces every existing tile
  and owns the whole work area.
- Applications replaced or squeezed out are only minimized. Their layout node is
  retained, so their split state survives in the background and remains visible
  in overview.
- Pane borders are draggable. Dragging a border until a neighbour has no room
  left backgrounds that neighbour and hands its space over. A split boundary is
  shared, so resizing one pane also resizes its neighbour.
- A lone tile resizes freely from any edge, including the margin exposed to the
  screen border. Its size is remembered across activation changes until it joins
  a split.
- The work area reserves a 51 logical-pixel top strip with a 16-pixel margin on
  the other edges, so resize borders stay reachable without a pointer cursor.

## Touch Dock

The top bar presents a touch Dock: a launcher entry, running/minimized window
icons, battery, clock, and a power entry that opens the session power surface
(restart, shut down, log out, suspend). Dock controls render without pill card
backgrounds.

## Input

- One-finger drag on a tile border resizes it. The border band is 16 logical
  pixels wide and includes the margin between the window and the work-area edge;
  the physical bottom edge is left to the home strip.
- Overview, the lock screen, the shade and other exclusive surfaces stay
  Flutter-owned; the compositor does not capture those contacts.

## Profiles

The gamepad profile forces nine workspaces and the Dwindle layout regardless of
stored desktop settings. Native work-area policy is applied at startup and on
every settings synchronization, so leaving the profile restores the user's
stored desktop configuration.
