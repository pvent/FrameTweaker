### FrameTweaker
* **Description:** A lightweight utility addon enabling repositioning, scaling, and visual tweaks for locked Blizzard UI frames (such as unit frames, casting bars, and micro menus) on the 2.5.3 client.
* **How to Use:**
  1. Unlock frames via the addon's configuration toggle.
  2. Drag frames to your desired position on the screen.
  3. Settings are automatically saved to your account/character `SavedVariables`.
* **Known Issues & Gotchas:**
  * **Combat Lockout (Taint):** Attempting to modify protected Blizzard frame attributes or anchors while actively engaged in combat will trigger Lua errors or block execution.
  * **Layout Reset on Patch Updates:** Interface scaling updates or game client refreshes can occasionally invalidate saved coordinate anchors, requiring a reset to default positions.
