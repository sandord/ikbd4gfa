# IKBD4GFA

Using the default keyboard and joystick functions in GFA Basic on the Atari ST has its limitations.

Especially when developing games, you may find that you need a more performant and reliable way of handling keyboard and joystick input.

This repository contains IKBD routines for keyboard and joystick handling that can be used in GFA Basic.

## Routines

The [dist/IKBD4GFA.INL](dist/IKBD4GFA.INL) file is an Atari ST binary, assembled from the [src/IKBD.S](src/IKBD.S) source using Devpac 3.

The following routines are available in the binary:

| Routine                  | Offset | Description                                                                                                     | Returns         | Supervisor mode |
|--------------------------|:------:|:----------------------------------------------------------------------------------------------------------------|-----------------|:---------------:|
| `init`                   |  +$1c  | Initializes the IKBD. Must be called before other routines.                                                     | -               |       Yes       |
| `restore`                |  +$20  | Restores the IKBD. Call before exiting your program.                                                            | -               |       Yes       |
| `disable_mouse`          |  +$24  | Disables mouse reporting from the IKBD to save CPU.                                                             | -               |       Yes       |
| `enable_mouse`           |  +$28  | Enables mouse reporting. Call at program end if you previously disabled the mouse.                              | -               |       Yes       |
| `get_scancode_state_tbl` |  +$2c  | Gets address of the scancode state table. Use scancode as index, `0` = unpressed, `1` = pressed.                | `a0` (address)  |       No        |
| `get_ascii_state_tbl`    |  +$30  | Gets address of the ASCII state table. Use ASCII code as index, `0` = unpressed, `1` = pressed.                 | `a0` (address)  |       No        |
| `get_last_scancode`      |  +$34  | Returns the scancode of the last pressed key.                                                                   | `d0` (scancode) |       No        |
| `get_joystick_states`    |  +$38  | Returns joystick states for joysticks 0 and 1 with joystick 0 state in the MSB and joystick 1 state in the LSB. | `d0` (states)   |       No        |
| `interrogate_joysticks`  |  +$3c  | Triggers joystick interrogation; states become available later and can be read with `get_joystick_states`.      | -               |       Yes       |

## Usage

To use the routines in GFA Basic, you should inline the [dist/IKBD4GFA.INL](dist/IKBD4GFA.INL) file in your GFA Basic program:

```basic
' IKBD4GFA.INL. Make sure the number in the second parameter matches the size
' of the .INL file exactly.
INLINE ikbd%,934
```

You can then load the `.INL` file in-line by pressing the `Help` key while the text cursor is on the `INLINE` keyword. Click on `Load` at the top of the screen and select the `.INL` file (it is located in the `/dist` directory of this repository).

Next, add the following code that makes the routine calls easier to use.

```basic
' This array represents the CPU registers d0-d7/a0-a6.
DIM reg%(15)
'
PROCEDURE init_ikbd
  ~XBIOS(38,L:ikbd%+&H1C) !init
RETURN
PROCEDURE restore_ikbd
  ~XBIOS(38,L:ikbd%+&H20) !restore
RETURN
PROCEDURE disable_mouse
  ~XBIOS(38,L:ikbd%+&H24) !disable_mouse
RETURN
PROCEDURE enable_mouse
  ~XBIOS(38,L:ikbd%+&H28) !enable_mouse
RETURN
FUNCTION get_last_scancode
  RCALL ikbd%+&H34,reg%()
  RETURN reg%(0) !d0
ENDFUNC
PROCEDURE interrogate_joysticks
  ~XBIOS(38,L:ikbd%+&H3C) !interrogate_joysticks
RETURN
FUNCTION get_joystick_states
  RCALL ikbd%+&H38,reg%() !get_joystick_states
  RETURN reg%(0) !d0
ENDFUNC
FUNCTION get_scancode_state_table
  RCALL ikbd%+&H2C,reg%() !get_scancode_state_tbl
  RETURN reg%(8) !a0
ENDFUNC
FUNCTION get_ascii_state_table
  RCALL ikbd%+&H30,reg%() !get_ascii_state_tbl
  RETURN reg%(8) !a0
ENDFUNC
```

> As you can see, the same offsets from the routine table mentioned earlier, are used in the calls. Also, note that some calls are made using `XBIOS(38,...)`, which calls the routine in supervisor mode.

## Demo code

The [demo/GFADEMO.LST](demo/GFADEMO.LST) file contains demo code for GFA Basic.

> The GFA source is present as a `.LST` file because it is in ASCII format while `.GFA` files are token-based. The token-based files wouldn't be previewable outside of the GFA Basic editor and they'd also make diffs and merges practically impossible.

You can load the `.LST` file into your GFA editor using the Merge option. Then you'll have to load the `IKBD4GFA.INL` file in-line (see instructions above).

## Known issues

- There's a bug that causes the mouse to be stuck after using the routines.
