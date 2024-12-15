# Manual execution of alert engine
python ~/GitHub/SQLMonitor/Alerting/SQLMonitorAlertEngineApp.py --inventory_server sqlmonitor --verbose True --login_password '<<SomeStringPasswordHereForInventoryServerLogin>>'

# ------------------------------------------------
# Alert Engine on Podman Container
# ------------------------------------------------
cd ~/GitHub/SQLMonitor/Alerting/

# Save inventory login/password in ~/.bashrc
echo 'export MSSQLPASSWORD="SomeStringPasswordHereForInventoryServerLogin"' >> ~/.bashrc
source ~/.bashrc

# Build pod
podman build -t sqlmonitor-alert-engine .

# Run pod in detached manner with arguments
podman run --replace -d -e inventory_server='sqlmonitor' -e login_password="$MSSQLPASSWORD" --name sqlmonitor-alert-engine -p 5000:5000 sqlmonitor-alert-engine

# Start the container in Interactive Mode Replacing Old container
podman run -it --replace -e inventory_server='sqlmonitor' -e login_password="$MSSQLPASSWORD" --name sqlmonitor-alert-engine -p 5000:5000 sqlmonitor-alert-engine /bin/bash

# Test
curl http://localhost:5000

# Manage container
podman ps

podman logs sqlmonitor-alert-engine
podman logs -f sqlmonitor-alert-engine
podman logs --tail 20 sqlmonitor-alert-enginepodman inspect sqlmonitor-alert-engine

# Start/Stop container
podman start sqlmonitor-alert-engine
podman stop sqlmonitor-alert-engine

# Remove container
podman rm -f sqlmonitor-app

# Start pod automatically
    # generate systemd files
    podman generate systemd --name sqlmonitor-alert-engine --files

    # enable it by moving files
    sudo mv sqlmonitor-alert-engine.service /etc/systemd/system/
    sudo systemctl enable sqlmonitor-alert-engine.service

