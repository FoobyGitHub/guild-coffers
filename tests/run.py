"""Run the Lua tests under Lua 5.1 (the WoW client's Lua version).

    pip install lupa
    python3 tests/run.py
"""
import os
import sys

from lupa.lua51 import LuaRuntime

root = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
os.chdir(root)
lua = LuaRuntime(unpack_returned_tuples=True)
try:
    lua.execute(open(os.path.join("tests", "test.lua")).read())
except Exception as exc:  # noqa: BLE001
    print(exc)
    sys.exit(1)
