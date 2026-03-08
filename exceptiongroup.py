"""Minimal compatibility shim for environments without the exceptiongroup package."""

from contextlib import contextmanager


class BaseExceptionGroup(Exception):
    """Fallback BaseExceptionGroup for Python environments lacking built-in support."""


class ExceptionGroup(BaseExceptionGroup):
    """Fallback ExceptionGroup for plugin imports."""


@contextmanager
def catch(_mapping):
    """No-op fallback context manager used by third-party plugins."""
    yield
