# Standard-library behavioral tests

Every top-level `std/*.mg` module must have exactly one matching test program in
this directory. `raylib.mg` is the sole exception because loading it requires an
external DLL and an interactive graphics environment.

`RUN_TESTS.bat` compiles each test as an executable and runs it. A test passes
only when compilation succeeds and its assertions exit successfully. Tests
must be deterministic and must not require network access or user input.
