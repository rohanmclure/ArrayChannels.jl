# Contributing to ArrayChannels.jl

## Contributing to the Software

Using the installation instructions described in `README.md`, downloaded source code can be staged for development via the `dev` commandlet of `Pkg`.

The project source consists of four files,

  - `ArrayChannels.jl` for imports as well as exporting public-facing methods.
  - `arraychannels.jl` for containing interface methods to the library including `reduce!` and `put!`, and the `ArrayChannel` object definition.
  - `inplacearray.jl` contains the key data type at use - an array wrapper that serialises in-place.
  - `precompile.jl` which will precompile method overloads which performance may depend upon.

  Welcome improvements to `ArrayChannels.jl` include a widening or optimisation of the communication operations that are permitted in the library. All new primitives must be cautious to retain the same advantages of temporal locality as obtainable currently.

  ## Reporting Issues or Suggesting Improvements to the Interface

  Issue reporting and recommendations should be provided through the _Issues_ tab on the _GitHub_ repository.

  ## Seeking Support

  Requests for assistance in the use of `ArrayChannels.jl` in your parallel codes can be directed to `rohan.mclure@anu.edu.au`, or otherwise lodged as issues on the `GitHub` issue tracker. I suggest flagging your request with the `help wanted` label.
