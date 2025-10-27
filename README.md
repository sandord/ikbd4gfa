# IKBD4GFA

IKBD routines for keyboard and joystick handling, for use with GFA Basic on the Atari ST. Aimed at game development. 

You can check out the assembly source in the `src` directory for usage details.

The source is written using Devpac 3.

## Demo code

The `demo` directory contains demo code for GFA Basic, showing the use of the routines.

The GFA source is present as a `.LST` file because it is in ASCII format while `.GFA` files are token-based, which makes diffs and merges practically impossible.

You can load the `.LST` file into your GFA editor using the Merge option. Then you'll have to load the `IKBD4GFA.INL` file in-line. You can do this by pressing the Help key while the text cursor is on the `INLINE` keyword at the top of the source code.

## Known issues

- At the moment the mouse can't be moved after using the routines.
