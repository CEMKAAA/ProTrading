# Exclude manual test scripts from pytest collection.
# test_bot.py is a standalone MT5 connectivity check, not a pytest suite.
collect_ignore = ["test_bot.py"]
