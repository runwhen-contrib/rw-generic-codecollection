"""
Relative-time helpers for RunWhen codebundles.

Robot keywords (callable from .robot files):

- ``Convert Relative Time To Sec Epoch``
- ``Convert Relative Time To Ms Epoch``
- ``Convert Relative Time To Nano Epoch``
- ``Convert Duration To Sec``
- ``Convert Duration To Ms``

All three accept a string like ``30m``, ``2h``, ``2d`` (suffix ``s/m/h/d``) and
return the corresponding epoch value of "now - X" in the requested unit.

Special inputs:

- ``""`` (empty) returns the **current time** in the requested unit.
- A non-relative value (anything that does not match ``<int><smhd>``) is
  returned unchanged, on the assumption that the caller has already prepared
  an absolute timestamp (e.g. RFC3339, or already-converted epoch value).

Example:

    | ${start_ns}=  | Convert Relative Time To Nano Epoch | 2h |
    | ${start_ms}=  | Convert Relative Time To Ms Epoch   | 2h |
    | ${start_sec}= | Convert Relative Time To Sec Epoch  | 2h |
"""

from __future__ import annotations

import re
import time
from typing import Tuple, Union

_RELATIVE_RE = re.compile(r"^(\d+)([smhd])$")
_UNIT_TO_SECONDS = {"s": 1, "m": 60, "h": 3600, "d": 86400}


class Time:
    """Robot Framework library exposing relative-time helpers."""

    ROBOT_LIBRARY_SCOPE = "GLOBAL"
    ROBOT_LIBRARY_VERSION = "1.0.0"

    @staticmethod
    def _now_seconds() -> int:
        return int(time.time())

    @classmethod
    def _classify(cls, time_string: Union[str, None]) -> Tuple[str, object]:
        """
        Returns one of:
        - ("now", None)
        - ("relative_seconds", <int seconds offset>)
        - ("literal", <original string>)
        """
        if time_string is None or time_string == "":
            return ("now", None)
        match = _RELATIVE_RE.match(str(time_string).strip())
        if match:
            amount = int(match.group(1))
            unit = match.group(2)
            return ("relative_seconds", amount * _UNIT_TO_SECONDS[unit])
        return ("literal", time_string)

    def convert_relative_time_to_sec_epoch(self, time_string: str) -> Union[int, str]:
        """
        Returns Unix epoch seconds for a relative time string ("30m", "2h",
        "2d"), the current time for an empty input, or the original string
        unchanged for an absolute value.
        """
        kind, value = self._classify(time_string)
        if kind == "now":
            return self._now_seconds()
        if kind == "relative_seconds":
            return self._now_seconds() - int(value)  # type: ignore[arg-type]
        return value  # type: ignore[return-value]

    def convert_relative_time_to_ms_epoch(self, time_string: str) -> Union[int, str]:
        """Same as ``convert_relative_time_to_sec_epoch`` but in milliseconds."""
        kind, value = self._classify(time_string)
        if kind == "now":
            return self._now_seconds() * 1000
        if kind == "relative_seconds":
            return (self._now_seconds() - int(value)) * 1000  # type: ignore[arg-type]
        return value  # type: ignore[return-value]

    def convert_relative_time_to_nano_epoch(self, time_string: str) -> Union[int, str]:
        """Same as ``convert_relative_time_to_sec_epoch`` but in nanoseconds."""
        kind, value = self._classify(time_string)
        if kind == "now":
            return self._now_seconds() * 1_000_000_000
        if kind == "relative_seconds":
            return (self._now_seconds() - int(value)) * 1_000_000_000  # type: ignore[arg-type]
        return value  # type: ignore[return-value]

    def convert_duration_to_sec(self, duration: str) -> Union[int, str]:
        """
        Convert a duration string ("15s", "1m", "2h") to integer seconds.
        Empty input returns 0. Non-matching input is returned unchanged.
        Useful for Prometheus-style ``step``/``intervalMs`` derivation.
        """
        if duration is None or duration == "":
            return 0
        match = _RELATIVE_RE.match(str(duration).strip())
        if match:
            amount = int(match.group(1))
            unit = match.group(2)
            return amount * _UNIT_TO_SECONDS[unit]
        return duration  # type: ignore[return-value]

    def convert_duration_to_ms(self, duration: str) -> Union[int, str]:
        """Convert a duration string to integer milliseconds (see ``convert_duration_to_sec``)."""
        secs = self.convert_duration_to_sec(duration)
        if isinstance(secs, int):
            return secs * 1000
        return secs
