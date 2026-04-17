#!/bin/bash
cd app/backend
docker build -t arsprod01/devops-backend:v1.0 .
docker push arsprod01/devops-backend:v1.0

cd ../frontend
docker build -t arsprod01/devops-frontend:v2.0 .
docker push arsprod01/devops-frontend:v2.0