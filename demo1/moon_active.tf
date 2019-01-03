
# VARIABLES
variable "dns_records" {type = "list"}
variable "services_ports" {type = "list"}

# Install Node + NPM + PM2
resource "null_resource" "init" {
  provisioner "local-exec" {
  command = <<EOT
      curl -o- https://raw.githubusercontent.com/creationix/nvm/v0.33.8/install.sh | bash
      . ~/.nvm/nvm.sh
      nvm install 9.3.0
      npm i -g pm2
      echo "export NVM_DIR"
      export NVM_DIR="$HOME/.nvm"
      echo "NVM_DIR/nvm.sh"
      [ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"  # This loads nvm
      echo "NVM_DIR/bash_completion"
      [ -s "$NVM_DIR/bash_completion" ] && \. "$NVM_DIR/bash_completion"
      echo ". ~/.bash_profile"
      . ~/.bash_profile #reload bash profile
      EOT
  }
}

# Create Nginx Repo
resource "local_file" "nginx_repo" {
    content = <<EOT
[nginx]
name=nginx repo
baseurl=http://nginx.org/packages/mainline/rhel/7/$basearch/
gpgcheck=0
enabled=1
EOT
    filename = "nginx.repo"
}

# Install NGINX & Configure  
resource "null_resource" "nginx" {
  depends_on = ["null_resource.init"]
    provisioner "local-exec" {
    command = <<EOT
           sudo mv nginx.repo /etc/yum.repos.d/
           sudo yum install nginx -y

           sudo mkdir /etc/nginx/sites-available
           sudo mkdir /etc/nginx/sites-enabled 

           sudo systemctl start nginx

          # NGINX Auto start
           sudo chkconfig nginx on
          EOT
    }
}

# Add to nginx.conf the following lines:
# include /etc/nginx/sites-enabled/*.conf;
# server_names_hash_bucket_size 64;
  resource "null_resource" "ngnix_conf"  {
    depends_on = ["null_resource.nginx"]
    provisioner "local-exec" {
      command = <<EOT
    #sudo sed -i '/include /etc/nginx/conf.d/*.conf;/c\ # include /etc/nginx/conf.d/*.conf;' /etc/nginx/nginx.conf
    #sed -i 's#/var/www#/home/lokesh/www#g' lks.php


    last_line=$(awk 'END {print NR}' /etc/nginx/nginx.conf)
    sudo sed -i "$last_line i server_names_hash_bucket_size 64;" /etc/nginx/nginx.conf
    sudo sed -i "$last_line i include /etc/nginx/sites-enabled/*.conf;" /etc/nginx/nginx.conf
          EOT
    }
  }

# Create Nginx Configuration file for each domain
resource "local_file" "create_nginx_conf_file" {
  depends_on = ["null_resource.ngnix_conf"]
  count = "${length(var.dns_records)}"
  content = <<EOT
  # the IP(s) on which your node server is running.
    upstream ${element(var.dns_records,count.index)} {
    server 127.0.0.1:${element(var.services_ports,count.index)};
    keepalive 8;
}

  # the nginx server instance
  server {
      listen 80;
      listen [::]:80;
      server_name ${element(var.dns_records,count.index)} www.${element(var.dns_records,count.index)};
      access_log /var/log/nginx/${element(var.dns_records,count.index)}.log;

      # pass the request to the node.js server with the correct headers
      # and much more can be added, see nginx config option
      location / {
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header Host $http_host;
        proxy_set_header X-NginX-Proxy true;

        proxy_pass http://${element(var.dns_records,count.index)}/;
        proxy_redirect off;
      }
  }
  EOT
  filename = "${element(var.dns_records,count.index)}.conf"
}

# Move ngnix conf files under sites-available
resource "null_resource" "move_ngnix_conf_files" {
  depends_on = ["local_file.create_nginx_conf_file"]
  count = "${length(var.dns_records)}"
  provisioner "local-exec" {
    
    command = <<EOT
         sudo mv ${element(var.dns_records,count.index)}.conf /etc/nginx/sites-available
         EOT
  }
}

# Create symb links
resource "null_resource" "enable_sites" {
  depends_on = ["null_resource.move_ngnix_conf_files"]
  count = "${length(var.dns_records)}"
  provisioner "local-exec" {
    
    command = <<EOT
         cd /etc/nginx/sites-enabled/ 
         sudo ln -s /etc/nginx/sites-available/${element(var.dns_records,count.index)}.conf ${element(var.dns_records,count.index)}.conf
         EOT
  }
}

 # Create the services
  resource "local_file" "services"  {
    depends_on = ["null_resource.enable_sites"]
    count = "${length(var.services_ports)}"
    content = <<EOT
  var http = require('http');

  http.createServer(function (req, res) {
  res.writeHead(200, {'Content-Type': 'text/plain'});
  res.end('Hello Service ${count.index+1}\n');
  }).listen(${element(var.services_ports,count.index)}, "127.0.0.1");
  console.log('Server running at http://127.0.0.1:${element(var.services_ports,count.index)}/');
      EOT
    filename = "service${count.index+1}.js"
  }

# Move services
resource "null_resource" "move_services" {
  depends_on = ["local_file.services"]
  provisioner "local-exec" {
    command = <<EOT
         sudo mv service*.js /usr/share/nginx
         EOT
  }
}

# Auto start services
resource "null_resource" "autostart_services" {
  depends_on = ["null_resource.move_services"]
  count = "${length(var.dns_records)}"
  provisioner "local-exec" {
    command = <<EOT
         pm2 start /usr/share/nginx/service${count.index+1}.js
         sleep 3
         EOT
  }
}

resource "null_resource" "restart" {
depends_on = ["null_resource.autostart_services"]
provisioner "local-exec" {
  command = <<EOT
        sudo systemctl reload nginx
        EOT
  }
}



