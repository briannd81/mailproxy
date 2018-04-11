# mailproxy
Sending email inside corporate network

This program can be used to send email from a source system that cannot have MTA installed.It will use another "jump box" that has MTA installed.

Source System Requirements:

1. KSH available

Jump Box Requirements:

1. Configure SMTP using sendmail or other MTA on jump box
2. Source system must be able to SSH to the jump box
3. mailx is available on the jump box
