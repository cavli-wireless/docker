# NOTE

## HOW TO RUN
- Choice a disk to run CICD. EX : /mnt/SSD17TB/CICD/SDX35
- Get github action token. EX : BCU4LE4VIBTEQUD6MDUH27LGIOCQM
- Make sure docker img "ghcr.io/cavli-wireless/cqs290/build_cqs290:latest" ready
- Run below cmd to create 4 local RUNNER !!!!!
    ```
    bash cicd_helper.sh -w /mnt/DATA_01/02_Cavli/CICD/SDX35/ -t /mnt/DATA_01/02_Cavli/Tools/cavli_cqs290_buildtools/ -n 4 -k BCU4LE4CMLCFPU6L766LCATGLBJB2
    ```
