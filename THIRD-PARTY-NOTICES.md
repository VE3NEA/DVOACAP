# Third-party notices

Everything in this repository is distributed under the MIT License (see `LICENSE`), with the
single exception recorded below.

## DVoaDll/3rdParty_Json/superobject.pas

The Super Object Toolkit, a JSON parser for Object Pascal.

- Unit owner: Henri Gourvest <hgourvest@gmail.com>, http://www.progdigy.com
- Contains patches by Daniele Teti <daniele.teti@gmail.com>
- Inspired by json-c, Michael Clark <michael@metaparadigm.com>
- Licensed by its authors under **either** the Lesser GNU General Public License **or** the
  Mozilla Public License 1.1, at the user's option.

This file is **not** covered by this repository's MIT License and is not ours to relicense. It is
used only by `dvoa.dll`, the JSON wrapper around the prediction engine, to parse the input
parameters and format the results.

The engine itself — everything under `DVoaClass` — has no dependency on it. Code that links
`DVoaClass` directly, rather than going through the DLL wrapper, carries no third-party licence
obligation from this repository.
