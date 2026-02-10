#!/usr/bin/env bash
################################
# STARTUP SCRIPT BASESTATION
# RUNS, CONFIGS AND CHECKS THE STARTUP FOR BASESTATIONS
# 
# AUTHOR: DOMENIC CHAO
# LAST UPDATED: FEB 09, 2026
# VERSION: 1.0.0D
################################

## GLOBAL COLOUR VARIBALES
GB='\033[1;32m'	#GREEN BOLD
RB='\033[1;31m' #RED BOLD
NC='\033[0m'	#NO COLOUR
NCB='\033[1m' 	#NO COLOUR BOLD

## GLOBAL VARS
VERSION='1.0.0 DEV'
NAME='BASESTATION' 					
PACKAGE='<package-name>'
SUBNET1=1
NIC1='eth0'
SUBNET2=2
NIC2='eth1'
ENV_VAR_NAMES=('ROS_AUTOMATIC_DISCOVERY_RANGE')
ENV_VAR_EXP_VALUES=('SUBNET')
IP_ADDR_FINAL_DIGIT=20
IP_ADDR_CLASS='192.168'

CRIT_ERROR=0		# DO NOT EDIT
CRIT_ERROR_MSG=''	# DO NOT EDIT
ELEVATED_PERM=0		# DO NOT EDIT
NETWORK_NAME1=''	# DO NOT EDIT
NETWORK_NAME2=''	# DO NOT EDIT
IP_ADDR1='192.168.1.20'	# DO NOT EDIT
IP_ADDR2='192.168.2.20'	# DO NOT EDIT

## PRINT FUNCTIONS
print_pass() {
	echo -e "${GB}PASS${NC}]"
}

print_fail() {
	echo -e "${RB}FAIL${NC}]"
}

## CHECKS
daemon_online() {
	return $(systemctl is-active docker | grep "active" -wq)
}

docker_installed() {
	return $(command -v docker | grep "docker" -q)
}

docker_sudo_access() {
	return 	$(groups $(logname) | grep "docker" -wq)
}

repo_pulled() {
	return $(docker image ls --format "{{.Repository}}:{{.Tag}}" | grep ${PACKAGE} -wq)
}

old_container_exist() {
	return $(docker container ps -a --format "{{.Names}}" | grep ${NAME} -wq)
}
check_env_vars() {	
	if [[ ${#ENV_VAR_NAMES[@]} -ne ${#ENV_VAR_EXP_VALUES[@]} ]]; then
		CRIT_ERROR=1
		CRIT_ERROR_MSG+='\tENV_VAR_NAME LENGTH DOESNT EQUAL ENV_VAR_EXP_VALUES LENGTH\n'
		return 1
	fi
	
	
	for (( INDEX = 0; INDEX < ${#ENV_VAR_NAMES[@]}; INDEX++ )); do
		if [[ $(docker exec -it ${NAME} bash -ic "env" | grep -wc ${ENV_VAR_NAMES[INDEX]}'='${ENV_VAR_EXP_VALUES[INDEX]}) -ne 1 ]]; then
			return 1
		fi
	done
		
	return 0
}

network_exists() {
	return $(docker network inspect $(docker network ls --filter type=custom -q) --format "{{.Name}} {{range .IPAM.Config}}{{.Subnet}}{{end}} {{.Options.parent}}" |grep ${NIC1} | awk '{ print $2 }' | awk -F "." '{ print $3 }' | grep ${SUBNET1} -wq) && $(docker network inspect $(docker network ls --filter type=custom -q) --format "{{.Name}} {{range .IPAM.Config}}{{.Subnet}}{{end}} {{.Options.parent}}" |grep ${NIC2} | awk '{ print $2 }' | awk -F "." '{ print $3 }' | grep ${SUBNET2} -wq)
}

container_online() {
	return $(docker ps --format '{{.Status}} {{.Names}}' | grep ${NAME} | grep 'Up' -wq)
}

check_network() {
	return $(ping ${IP_ADDR1} -c 1 2>/dev/null| grep -wq "ttl") && $(ping ${IP_ADDR2} -c 1 2>/dev/null | grep -wq "ttl")
}
	
## ATTEMPTING FIX COMMANDS
start_container() {	
	ENV_VARS_LINE=''

	if [[ ${#ENV_VAR_NAMES[@]} -eq ${#ENV_VAR_EXP_VALUES[@]} ]]; then
		for (( INDEX = 0; INDEX < ${#ENV_VAR_NAMES[@]}; INDEX++ )); do
			ENV_VARS_LINE+=" -e ${ENV_VAR_NAMES[INDEX]}=${ENV_VAR_EXP_VALUES[INDEX]}"
		done
	fi
	
	docker run --rm -d --network ${NETWORK_NAME1} --ip ${IP_ADDR1} --name ${NAME} ${ENV_VARS_LINE} ${PACKAGE} sleep infinity &> /dev/null
	docker network connect --ip ${IP_ADDR2} ${NETWORK_NAME2} ${NAME}
	docker exec -it ${NAME} bash -ic 'source /opt/ros/humble/setup.bash; echo "source /opt/ros/humble/setup.bash" >> ~/.bashrc'
}

install_docker() {
	echo -e -n "\tATTEMPTING INSTALL:\t["
	if [[ $ELEVATED_PERM -ne 0 ]]; then
		sudo apt update
		sudo apt install -y docker.io
		sudo systemctl enable docker --now
		docker
		
		sudo usermod -aG docker $(logname)
	fi
	
	if docker_installed; then
		print_pass
	else
		print_fail
		CRIT_ERROR=1
		CRIT_ERROR_MSG+='\tUNABLE TO INSTALL DOCKER\n'
	fi
}

start_docker() {
	echo -e -n "\tATTEMPTING TO START:\t["
	
	if [[ $ELEVATED_PERM -ne 0 ]]; then
		sudo systemctl start docker
	fi
	
	if daemon_online; then
		print_pass
	else
		print_fail
		CRIT_ERROR=1
		CRIT_ERROR_MSG+='\tUNABLE TO RESTART DAEMON; TRY RUNNING "sudo systemctl start docker"\n'
	fi
}

provide_docker_access() {
	echo -e -n "\tATTEMPTING TO ELEVATE DOCKER ACCESS:\t["
	
	if [[ $ELEVATED_PERM -ne 0 ]]; then
		sudo usermod -aG docker $(logname)
	fi
	
	if docker_sudo_access; then
		print_pass
	else
		print_fail
		CRIT_ERROR=1	
		CRIT_ERROR_MSG+='\tDOCKER DOESNT HAVE ELAVATED PERMISSIONS RUN "sudo usermod -aG docker $(logname)"\n'
	fi
}

pull_repo() {
	echo -e -n "\tPULLING REPO:\t["

	docker pull ${PACKAGE}
	
	if repo_pulled; then
		print_pass
	else
		print_fail
		CRIT_ERROR=1
		CRIT_ERROR_MSG+='\tDOCKER PACKAGE NOT PULLED, TRY RUNNING "docker pull' + ${PACKAGE} + '"\n'
	fi
}

remove_old_container() {
	echo -e -n "\tRM OLD CONTAINER:\t["
	
	docker container stop ${NAME} &> /dev/null
	docker container rm ${NAME} &> /dev/null
	
	if old_container_exist; then
		print_fail
		CRIT_ERROR=1
		CRIT_ERROR_MSG+='\tUNABLE TO REMOVE OLD CONTAINER\n'
	else
		print_pass
	fi	
}

set_env_vars() {	
	echo -e -n "\tATTEMPTING TO SET ENV VAR:\t["
	
	for (( INDEX = 0; INDEX < ${#ENV_VAR_NAMES[@]}; INDEX++ )); do
		if [[ $(docker exec -it ${NAME} bash -ic "env" | grep -wc ${ENV_VAR_NAMES[INDEX]}'='${ENV_VAR_EXP_VALUES[INDEX]}) -ne 1 ]]; then
			CMD='echo \"export ${ENV_VAR_NAMES[INDEX]}=${ENV_VAR_EXP_VALUES[INDEX]}\" >> ~./bashrc'
			docker exec ${NAME} bash -ic "${CMD}"
		fi
	done
	
	if check_env_vars; then 
		print_pass
	else
		print_fail
		CRIT_ERROR=1
		CRIT_ERROR_MSG+="\tUNABLE TO SET ENV VARIABLES"
	fi
}

## MAIN
if [[ $EUID -eq 0 || -n "$SUDO_USER" ]]; then
	ELEVATED_PERM=1
fi

echo -e "${NCB}//-----------STARTUP-${NAME}------------//${NC}"
echo -e "VERSION: ${VERSION}"

## IS ELEVATED MODE
if [[ $ELEVATED_PERM -ne 0 ]]; then
	echo -e "${RB}ELEVATED PERMISSION MODE${NC}"
fi
echo -e ""

## CHECKING IF DOCKER IS INSTALLED
echo -e -n "DOCKER INSTALLED:\t\t["
if [[ ${CRIT_ERROR} -eq 0 ]]; then
	if docker_installed && [[ ${CRIT_ERROR} -eq 0 ]]; then
		print_pass
	else
		print_fail
		if [[ ${CRIT_ERROR} -eq 0 ]]; then
			install_docker
		fi
	fi
else
	print_fail
fi

## CHECKING IF DAEMON IS ONLINE
echo -e -n "DAMEMON ONLINE:\t\t\t["
if [[ ${CRIT_ERROR} -eq 0 ]]; then
	if daemon_online && [[ ${CRIT_ERROR} -eq 0 ]]; then
		print_pass
	else 
		print_fail
		if [[ ${CRIT_ERROR} -eq 0 ]]; then
			start_docker
		fi
	fi
else
	print_fail
fi

## CHECKING FOR SUDO ACCESS
echo -e -n "SUDO ACCESS:\t\t\t["
if [[ ${CRIT_ERROR} -eq 0 ]]; then
	if docker_sudo_access; then
		print_pass
	else
		print_fail
		if [[ ${CRIT_ERROR} -eq 0 ]]; then
			provide_docker_acess	
		fi
	fi
else
	print_fail
fi

## CHECKING IF PACKAGE IS PULLED
echo -e -n "REPO PULLED:\t\t\t["
if [[ ${CRIT_ERROR} -eq 0 ]]; then
	if repo_pulled; then
		print_pass
	else	
		print_fail
		
		if [[ ${CRIT_ERROR} -eq 0 ]]; then
			pull_repo
		fi
	fi
else
	print_fail
fi

## ENSURE NO OLD CONTAINERS EXIST
echo -e -n "NO OLD CONTAINER:\t\t["
if [[ ${CRIT_ERROR} -eq 0 ]]; then
	if old_container_exist; then
		print_fail
		
		if [[ ${CRIT_ERROR} -eq 0 ]]; then
			remove_old_container	
		fi
	else
		print_pass
	fi
else
	print_fail
fi

## ENSURING THAT NETWORK EXISTS
echo -e -n "NETWORK EXISTS:\t\t\t["

if [[ ${CRIT_ERROR} -eq 0 ]]; then
	if network_exists; then
		print_pass
		NETWORK_NAME1=$(docker network inspect $(docker network ls --filter type=custom -q) --format "{{.Name}} {{range .IPAM.Config}}{{.Subnet}}{{end}} {{.Options.parent}}" |grep ${NIC1} | awk '{ print $1 }')
		IP_ADDR1=$IP_ADDR_CLASS
		IP_ADDR1+="."$SUBNET1
		IP_ADDR1+="."$IP_ADDR_FINAL_DIGIT
		
		NETWORK_NAME2=$(docker network inspect $(docker network ls --filter type=custom -q) --format "{{.Name}} {{range .IPAM.Config}}{{.Subnet}}{{end}} {{.Options.parent}}" |grep ${NIC2} | awk '{ print $1 }')
		IP_ADDR2=$IP_ADDR_CLASS
		IP_ADDR2+="."$SUBNET2
		IP_ADDR2+="."$IP_ADDR_FINAL_DIGIT
		
		
	else
		print_fail
		
		echo -e -n "\tCREATING NETWORK:\t["
		if [[ $(ip route | grep ${NIC1} | awk '{ print $1 }' | awk -F '.' '{ print $3 }') -eq $SUBNET1 &&  $(ip route | grep ${NIC1} | awk '{ print $1 }' | awk -F '.' '{ print $1"."$2 }') -eq $IP_ADDR_CLASS ]]; then
			NETWORK_ID=1
			NETWORK_NAME1="MACVLAN-"
			NETWORK_NAME1_FOUND=0
			
			while [[ ${NETWORK_NAME1_FOUND} -eq 0 ]]; do
				if $(docker network inspect $(docker network ls --filter type=custom -q) --format "{{.Name}} {{range .IPAM.Config}}{{.Subnet}}{{end}} {{.Options.parent}}" |grep ${NETWORK_NAME1}${NETWORK_ID}); then
					NETWORK_NAME1_FOUND=1
					NETWORK_NAME1+=${NETWORK_ID}
				fi
					((NETWORK_ID++))
			done
			
			docker network create -d macvlan --SUBNET1=${IP_ADDR_CLASS}"."${SUBNET1}".0" --gateway=${IP_ADDR_CLASS}"."${SUBNET1}".1" -o parent=${NIC1} ${NETWORK_NAME1}
			
			if network_exists; then 
				print_pass
			else
				print_fail
				CRIT_ERROR=1
				CRIT_ERROR_MSG='\tUNABLE TO CREATE NEW NETWORK\n'
			fi
		elif [[ $(ip route | grep ${NIC2} | awk '{ print $1 }' | awk -F '.' '{ print $3 }') -eq $SUBNET2 &&  $(ip route | grep ${NIC2} | awk '{ print $1 }' | awk -F '.' '{ print $1"."$2 }') -eq $IP_ADDR_CLASS ]]; then
			NETWORK_ID=1
			NETWORK_NAME2="MACVLAN-"
			NETWORK_NAME2_FOUND=0
			
			while [[ ${NETWORK_NAME2_FOUND} -eq 0 ]]; do
				if $(docker network inspect $(docker network ls --filter type=custom -q) --format "{{.Name}} {{range .IPAM.Config}}{{.Subnet}}{{end}} {{.Options.parent}}" |grep ${NETWORK_NAME2}${NETWORK_ID}); then
					NETWORK_NAME2_FOUND=1
					NETWORK_NAME2+=${NETWORK_ID}
				fi
					((NETWORK_ID++))
			done
			
			docker network create -d macvlan --SUBNET1=${IP_ADDR_CLASS}"."${SUBNET2}".0" --gateway=${IP_ADDR_CLASS}"."${SUBNET2}".1" -o parent=${NIC2} ${NETWORK_NAME2}
			
			if network_exists; then 
				print_pass
			else
				print_fail
				CRIT_ERROR=1
				CRIT_ERROR_MSG='\tUNABLE TO CREATE NEW NETWORK\n'
			fi
		else
			CRIT_ERROR=1
			CRIT_ERROR_MSG='\tUNABLE TO CREATE NEW NETWORK\n'
		fi
	fi
else
	print_fail
fi

## STARTING AND CHECKING IF CONTAINER IS ONLINE
echo -e -n "STARTING CONTAINER:\t\t["
start_container
print_pass

## ENSURING CONTAINER IS ONLINE
echo -e -n "CONTAINER ONLINE:\t\t["
if [[ ${CRIT_ERROR} -eq 0 ]]; then
	if container_online; then
		print_pass
	else
		print_fail
		
		if [[ ${CRIT_ERROR} -eq 0 ]]; then
			remove_old_container
			start_container
			
			echo -e -n "\tRESTARTING CONTAINER:\t["
			if container_online; then
				print_pass
			else
				print_fail
				CRIT_ERROR=1
				CRIT_ERROR_MSG+='\tFAILED TO START DOCKER CONTAINER\n'
			fi
		fi
	fi
else
	print_fail
fi

## CHECKING ENV VARIBALES
echo -e -n "ENVIROMENT VARIABLE:\t\t["
if [[ ${CRIT_ERROR} -eq 0 ]]; then
	if check_env_vars; then
		print_pass
	else
		print_fail
		if [[ ${CRIT_ERROR} -eq 0 ]]; then
			set_env_vars
		fi
	fi
else
	print_fail
fi

##CHECKING NETWORK VISABLE ON HOST
echo -e  -n "NETWORK VISABLE:\t\t["
if [[ ${CRIT_ERROR} -eq 0 ]]; then
	if check_network; then
		print_pass
	else
		print_fail
		CRIT_ERROR=1
		CRIT_ERROR_MSG="\tUNABLE TO PING CONTAINER ON ${IP_ADDR1}. CHECK HOST CONFIGURATION AND TRY TO PING FROM EXTERNAL DEVICE"
	fi
else
	print_fail
fi


# FINAL PASS/FAIL STATUS (CRIT ONLY CAUSE FAIL)
echo -e -n "\nFINAL STATUS:\t\t\t["
if [[ ${CRIT_ERROR} -eq 0 ]]; then
	print_pass
else
	print_fail
	echo -e "${RB}CRIT_ERRORS_MSG:${NC}\n${CRIT_ERROR_MSG}"
fi

echo -e "${NCB}//------END-OF-STARTUP-PROCEDURE---------//${NC}"

if [[ ${CRIT_ERROR} -eq 0 ]]; then
	echo -e "${NCB}\nOPENING DOCKER TERMINAL:${NC}"
	docker exec -it ${NAME} bash
fi
