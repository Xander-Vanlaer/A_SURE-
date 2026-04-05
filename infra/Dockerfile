# Use Python base image
FROM python:3.11-slim

# Set working directory
WORKDIR /app

# Copy requirements and install dependencies
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

# Copy all app code into the container
COPY . .

# Expose port 80 for Azure
EXPOSE 80

# Environment variables for Flask
ENV FLASK_APP=crudapp.py
ENV FLASK_RUN_HOST=0.0.0.0
ENV FLASK_RUN_PORT=80

# Create the database tables then start Flask
# db.create_all() runs once on startup to ensure the 'entry' table exists
CMD python -c "from app import db; from crudapp import app; app.app_context().push(); db.create_all()" && flask run