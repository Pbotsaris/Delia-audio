from setuptools import setup, Extension
from builder import ZigBuilder

_pydelia = Extension("_pydelia", sources=["../src/python.zig"])

setup(
    name="pydelia",
    version="0.0.1",
    description="delia bindings",
    ext_modules=[_pydelia],
    cmdclass={"build_ext": ZigBuilder},
    package_data={"": ["", "*.pyi"]},
    packages=["pydelia"],
)

