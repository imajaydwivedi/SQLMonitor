import smtplib, ssl
from email.mime.text import MIMEText
from email.mime.multipart import MIMEMultipart

def send_email_alert_notification(smtp_server:str, smtp_server_port:int, smtp_account_name:str, smtp_account_password:str, logger=None, verbose:bool=False, **kwargs):
    alert_sender_email = kwargs['alert_sender_email']
    alert_receiver_email = kwargs['alert_receiver_email']
    alert_mail_subject = kwargs['alert_mail_subject']
    alert_mail_body = kwargs['alert_mail_body']

    message = MIMEMultipart("alternative")
    message["Subject"] = alert_mail_subject
    message["From"] = alert_sender_email
    message["To"] = alert_receiver_email

    # Add HTML/plain-text parts to MIMEMultipart message
    # The email client will try to render the last part first
    message.attach(MIMEText(alert_mail_body, "html"))

    # Create secure connection with server and send email
    context = ssl.create_default_context()
    with smtplib.SMTP(smtp_server, smtp_server_port) as server:
        server.starttls(context=context)
        server.login(smtp_account_name, smtp_account_password)
        server.sendmail(alert_sender_email, alert_receiver_email, message.as_string())

