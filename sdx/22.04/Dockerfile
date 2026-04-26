# Use the base image
FROM ghcr.io/cavli-wireless-public/sdx/jammy/owrt:latest

# Create a user group with GID 1000
RUN groupadd -g 1000 khoad

# Create a user with UID 1000 and add to the group with GID 1000
RUN useradd -u 1000 -g 1000 -m -s /bin/bash khoad
RUN usermod -aG sudo khoad

# Grant the user sudo privileges (optional)
RUN echo 'khoad ALL=(ALL) NOPASSWD:ALL' >> /etc/sudoers

# Set the default user to khoad
USER khoad

# Set the command to run /data/run.sh
CMD ["bash"]

