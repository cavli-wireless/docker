# Use the base image
FROM ghcr.io/cavli-wireless/sdx35/jammy/owrt:latest

# Create a user group with GID 1000
RUN groupadd -g 1004 khoado

# Create a user with UID 1000 and add to the group with GID 1000
RUN useradd -u 1002 -g 1004 -m -s /bin/bash khoado
RUN usermod -aG sudo khoado

# Grant the user sudo privileges (optional)
RUN echo 'khoado ALL=(ALL) NOPASSWD:ALL' >> /etc/sudoers

# Set the default user to khoado
USER khoado

# Set the command to run /data/run.sh
CMD ["bash"]
