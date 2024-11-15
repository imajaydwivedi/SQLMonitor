import logging
import os
import sys
from logging.handlers import RotatingFileHandler

def get_script_logger(script_name:str,log_file:str=None):
    # create logger
    logger = logging.getLogger(script_name)
    logger.setLevel(logging.DEBUG)

    # create console handler and set level to debug
    ch = logging.StreamHandler(sys.stdout)
    ch.setLevel(logging.DEBUG)

    # create formatter
    formatter = logging.Formatter('%(asctime)s - %(name)s - %(levelname)s - %(message)s')

    # add formatter to ch
    ch.setFormatter(formatter)

    if log_file:
        #log_file_path = f"SQLMonitor-AlertEngine-Logs.log"
        max_log_size = 5 * 1024 * 1024  # 5 MB
        backup_count = 4  # Number of backup logs to keep

        # Ensure to create Logs directory is not exists
        log_dir = os.path.dirname(log_file)
        if not os.path.exists(log_dir):
            os.makedirs(log_dir)

        # Create a RotatingFileHandler
        fh = RotatingFileHandler(
            log_file, maxBytes=max_log_size, backupCount=backup_count
        )

        #fh = logging.FileHandler(log_file)
        fh.setLevel(logging.DEBUG)
        fh.setFormatter(formatter)
        logger.addHandler(fh)
        print(f"\nLogging to file '{log_file}'.\n")
    else:
        # add ch to logger
        print(f"Using console logger..")
        logger.addHandler(ch)

    return logger