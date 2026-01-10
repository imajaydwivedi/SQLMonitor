# find existing powerplans
powercfg -l

# add "Ultimate Performance" mode option
powercfg -duplicatescheme e9a42b02-d5df-448d-aa00-03f14749eb61

# Enable "Ultimate Performance" mode
powercfg -l
powercfg.exe -SETACTIVE <<guid_of_Ultimate_performance>>