import logging
import sys
import os
from datetime import datetime

# Global logger instance
logger = None

def init_logger():
    """Initialize the debug logger for Python server"""
    global logger
    if logger is None:
        logger = logging.getLogger('macdbg_python')
        logger.setLevel(logging.DEBUG)
        
        # Create console handler
        handler = logging.StreamHandler(sys.stderr)
        handler.setLevel(logging.DEBUG)
        
        # Create formatter
        formatter = logging.Formatter('[%(asctime)s] [Python] %(levelname)s: %(message)s')
        handler.setFormatter(formatter)
        
        # Add handler to logger
        logger.addHandler(handler)
        
        logger.info("MacDBG Python debug logger initialized")
    
    return logger

def log(message, category="INFO"):
    """Log a general message"""
    if logger is None:
        init_logger()
    logger.info(f"[{category}] {message}")

def log_error(message, exception=None):
    """Log an error message"""
    if logger is None:
        init_logger()
    if exception:
        logger.error(f"{message}: {str(exception)}")
    else:
        logger.error(message)

def log_crash(message):
    """Log a crash/critical error"""
    if logger is None:
        init_logger()
    logger.critical(f"CRASH: {message}")

def log_communication(direction, message):
    """Log communication between Swift and Python"""
    if logger is None:
        init_logger()
    logger.debug(f"COMM-{direction}: {message}")

def log_python_server(message):
    """Log Python server specific messages"""
    if logger is None:
        init_logger()
    logger.info(f"[SERVER] {message}")

def log_lldb(message):
    """Log LLDB specific messages"""
    if logger is None:
        init_logger()
    logger.info(f"[LLDB] {message}")
