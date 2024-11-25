AWS infrastructure for assignment

# Install Jenkins

sudo apt update

sudo apt install fontconfig openjdk-17-jre

java -version

sudo wget -O /usr/share/keyrings/jenkins-keyring.asc \
    https://pkg.jenkins.io/debian-stable/jenkins.io-2023.key

echo "deb [signed-by=/usr/share/keyrings/jenkins-keyring.asc]" \
    https://pkg.jenkins.io/debian-stable binary/ | sudo tee \
    /etc/apt/sources.list.d/jenkins.list > /dev/null

sudo apt-get update

sudo apt-get install fontconfig openjdk-17-jre

sudo apt-get install jenkins

sudo systemctl start jenkins

sudo systemctl enable jenkins

sudo systemctl status jenkins

sudo cat /var/lib/jenkins/secrets/initialAdminPassword

Access to http://public-ip:8080

# Connect to EKS in terminal for kubectl
aws configure

aws eks --region ap-southeast-1 update-kubeconfig --name sd2660-devops-eks

kubectl get all

* Note: Cannot execute kubectl command
Add IAM access entry to sd2660-devops-eks with AmazonEKSAdminPolicy and AmazonEKSClusterAdminPolicy

Add AmazonEBSCSIDriverPolicy to node group IAM role