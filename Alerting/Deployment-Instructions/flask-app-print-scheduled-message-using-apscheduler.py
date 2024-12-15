# Name this file as <<<<hello.py>>>>

from apscheduler.schedulers.background import BackgroundScheduler
from flask import Flask, current_app
from datetime import datetime
from waitress import serve

def create_app(config=None):
    """
    Factory function to create and configure the Flask application.
    """
    app = Flask(__name__)

    # Add configuration values directly
    #app.config['DBA_DATABASE'] = 'DBATools'
    #app.config['LOGIN_PASSWORD'] = 'SomeStringPassword'

    # Load default configurations
    app.config.from_mapping(
        DBA_DATABASE="DefaultDB",
        LOGIN_PASSWORD="DefaultPassword"
    )

    # Apply custom configuration if provided
    if config:
        app.config.update(config)

    def log_current_time():
        print(f"Current timestamp: {datetime.now().isoformat()}")

    # Function to start the scheduler only once
    def start_scheduler():
        if not hasattr(app, "scheduler_started"):
            app.scheduler_started = True  # Flag to prevent multiple initializations
            scheduler = BackgroundScheduler()
            scheduler.add_job(func=log_current_time, trigger="interval", seconds=30)
            scheduler.start()

    start_scheduler()

    @app.route("/")
    def hello_world():
        # Retrieve configurations from the Flask app
        dba_database = app.config.get('DBA_DATABASE')
        login_password = app.config.get('LOGIN_PASSWORD')

        print(f"dba_database: {dba_database}, login_password: {login_password}")
        print (f"Database: {app.config['DBA_DATABASE']}, Password: {app.config['LOGIN_PASSWORD']}")

        return "<p>Hello, World!</p>"

    # some utility function
    def some_function():
        # Access configurations in a non-route function
        dba_database = current_app.config['DBA_DATABASE']
        login_password = current_app.config['LOGIN_PASSWORD']
        print(f"Database: {dba_database}, Password: {login_password}")

    return app

# When running the script directly, use Waitress server
if __name__ == "__main__":
    print("Starting the app using Waitress server...")

    # Initialize the Flask application
    application = create_app({
        "DBA_DATABASE": "DBATools",
        "LOGIN_PASSWORD": "SomeStringPassword"
    })

    serve(application, host="0.0.0.0", port=8000)


'''
Code for wsgi.py
----------------------------------------------------------------

from hello import create_app
from waitress import serve

# Initialize the Flask application
application = create_app({
    "DBA_DATABASE": "DBATools",
    "LOGIN_PASSWORD": "SomeStringPassword"
})

# When running the script directly, use Waitress server
if __name__ == "__main__":
    print("Starting the app using Waitress server...")
    serve(application, host="0.0.0.0", port=8000)

'''

'''
# Deploy directly with gunicorn using 4 threads
#gunicorn -w 4 -b 0.0.0.0:8000 hello:app
#python wsgi.py
#gunicorn -w 4 wsgi:application

'''