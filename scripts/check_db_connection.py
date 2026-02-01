#!/usr/bin/env python3
"""
check_db_connection.py - Test PostgreSQL database connectivity

This script attempts to connect to a PostgreSQL database using the
provided connection parameters. It's used as a fallback when pg_isready
is not available in the container.

Usage:
    python3 check_db_connection.py <host> <port> <dbname> <user>
    
Note: Password must be provided via PGPASSWORD environment variable
      for security (avoids exposure in process listings)

Exit codes:
    0 - Successfully connected to database
    1 - Connection failed
    2 - Missing required arguments or PGPASSWORD
"""

import sys
import os

def check_connection(host, port, dbname, user, password):
    """Test database connection using psycopg2"""
    import psycopg2
    try:
        conn = psycopg2.connect(
            host=host,
            port=port,
            dbname=dbname,
            user=user,
            password=password,
            connect_timeout=2
        )
        conn.close()
        return True
    except (psycopg2.Error, OSError) as e:
        # Catch database connection errors and network errors
        # but allow system signals (KeyboardInterrupt, SystemExit) to propagate
        return False

def main():
    if len(sys.argv) != 5:
        print("Error: Missing required arguments", file=sys.stderr)
        print("Usage: python3 check_db_connection.py <host> <port> <dbname> <user>", file=sys.stderr)
        print("Note: Set PGPASSWORD environment variable for password", file=sys.stderr)
        sys.exit(2)
    
    host = sys.argv[1]
    port = sys.argv[2]
    dbname = sys.argv[3]
    user = sys.argv[4]
    password = os.environ.get('PGPASSWORD', '')
    
    if not password:
        print("Error: PGPASSWORD environment variable not set", file=sys.stderr)
        sys.exit(2)
    
    if check_connection(host, port, dbname, user, password):
        sys.exit(0)
    else:
        sys.exit(1)

if __name__ == '__main__':
    main()
