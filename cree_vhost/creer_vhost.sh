#!/bin/bash

#	-------------------------------------------------------------------
#
#	Shell program to creation d'un virtual host.
#
#	Copyright 2009, clem <cy.altern@gmail.com>.
#
#	This program is free software; you can redistribute it and/or
#	modify it under the terms of the GNU General Public License as
#	published by the Free Software Foundation; either version 2 of the
#	License, or (at your option) any later version. 
#
#	This program is distributed in the hope that it will be useful, but
#	WITHOUT ANY WARRANTY; without even the implied warranty of
#	MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the GNU
#	General Public License for more details.
#
#	Description: ce script accompli toutes les operations necessaires lors
#				 de la creation d'un virtual host: 
#					- creation du compte unix proprio
#					- creation du fichier vhost
#					- creation de l'arborescence + droits
#					- creation de(s) base(s) de donnees MySQL
#
#
#	Revision History:
#
#	04/21/2009	File created by new_script ver. 2.1.0
# 09/10/2013  passage de tous les chemins et parametres fixes en variables parametrees dans la section de depart "Constantes"
#
#	-------------------------------------------------------------------


#	-------------------------------------------------------------------
#	Constantes dependantes de la conf du serveur
#	-------------------------------------------------------------------
  # le programme
	PROGNAME=$(basename $0)
	VERSION="0.1.0"
  
  # IP du serveur et mail admin
  IP_SERVEUR="123.123.123.123"
  MAIL_SERVEUR_ADMIN="truc@mondomaine.org"
  
  # user qui fait tourner apache (www-data pour un serveur sous Debian)
  USER_APACHE="www-data"
  
  # le rep parent des vhosts 
  # + sa version avec / echappes pour compatibilite expression de remplacement de sed
  REP_VHOSTS="/home1/virtuals"
  REP_VHOSTS_ECHAP="\/home1\/virtuals"
  
  # le rep des fichiers de conf des vhosts d'apache
  REP_APACHE_CONF="/etc/apache2/vhosts.d"
  # le rep des fichiers de conf d'awstats
  REP_AWSTATS_CONF="/etc/awstats"
  
  # le repertoire de stockage des fichiers de conf et memo generes par ce script
  REP_STOCKAGE="/home/clem/stocks_vhosts"
  # l'user linux proprio de ce repertoire
  USER_STOCKAGE="clem"
  
  # l'utilisateur MySQL qui cree les nouvelles bases et les utilisateurs
  # doit avoir les privileges create_priv et reload_priv sur le serveur MySQL
  # et insert_priv, update_priv et delete_priv sur la table mysql
	USER_MYSQL="mon_user"
  PASS_MYSQL="mon_pass"
  
  # le chemin de phpmyadmin pour les liens symboliques
  #  CHEMIN_PHPMYADMIN="/home2/virtuals/pma.krakatoa.ww7.be/html/phpmyadmin"
  # URL generale de phpmyadmin pour le serveur
  URL_PHPMYADMIN="http://mondomaine.org/phpmyadmin"
  
  # le chemin du repertoire contenant le script de generation d'une instance de mutu de SPI
  # absolu ou relatif a ce fichier
  CHEMIN_CREE_SPIP="/home/clem/cree_spip"
  

#	-------------------------------------------------------------------
#	Functions
#	-------------------------------------------------------------------


function clean_up
{
#	-----------------------------------------------------------------------
#	Function to remove temporary files and other housekeeping
#		No arguments
#	-----------------------------------------------------------------------

	rm -f ${TEMP_FILE1}
}


function error_exit
{

#	-----------------------------------------------------------------------
#	Function for exit due to fatal program error
#		Accepts 1 argument:
#			string containing descriptive error message
#	-----------------------------------------------------------------------

	echo "${PROGNAME}: ${1:-"Unknown Error"}" >&2
	clean_up
	exit 1
}


function graceful_exit
{
#	-----------------------------------------------------------------------
#	Function called for a graceful exit
#		No arguments
#	-----------------------------------------------------------------------

	clean_up
	exit
}


function signal_exit
{

#	-----------------------------------------------------------------------
#	Function to handle termination signals
#		Accepts 1 argument:
#			signal_spec
#	-----------------------------------------------------------------------

	case $1 in
		INT)	echo "$PROGNAME: Programme abandonne par l'utilisateur" >&2
			clean_up
			exit
			;;
		TERM)	echo "$PROGNAME: Programme termine" >&2
			clean_up
			exit
			;;
		*)	error_exit "$PROGNAME: termine pour une erreur inconnue!"
			;;
	esac
}


function make_temp_files
{

#	-----------------------------------------------------------------------
#	Function to create temporary files
#		No arguments
#	-----------------------------------------------------------------------

	# Use user's local tmp directory if it exists

	if [ -d ~/tmp ]; then
		TEMP_DIR=~/tmp
	else
		TEMP_DIR=/tmp
	fi

	# Temp file for this script, using paranoid method of creation to
	# insure that file name is not predictable.  This is for security to
	# avoid "tmp race" attacks.  If more files are needed, create using
	# the same form.

	TEMP_FILE1=$(mktemp -q "${TEMP_DIR}/${PROGNAME}.$$.XXXXXX")
	if [ "$TEMP_FILE1" = "" ]; then
		error_exit "impossible de creer un fichier temporaire!"
	fi
}


function usage
{

#	-----------------------------------------------------------------------
#	Function to display usage message (does not exit)
#		No arguments
#	-----------------------------------------------------------------------

	echo "Usage: ${PROGNAME} [-h | --help] [-d ndd] [-n numero] [-u unix_user] [-s mysql_user] [-p mysql_pass] [-b mysql_base] [-q  mysql_nb] [-m mail_responsable] [-a creer_awstats] [-i init_mutu]"
}


function helptext
{

#	-----------------------------------------------------------------------
#	Function to display help message for program
#		No arguments
#	-----------------------------------------------------------------------

	local tab=$(echo -en "\t\t")

	cat <<- -EOF-

	${PROGNAME} ver. ${VERSION}
	Script de creation d'un virtual host.

	$(usage)

	Options:

	-h, --help	Display this help message and exit.
	-d  ndd          nom de domaine (avec le tld final)
	-n  numero       chiffre prefixe du nom de fichier de vhost
	-u  unix_user    nom de l'utilisateur unix a creer
	-x  unix_pass	   mot de passe de l'utilisateur
	-s  mysql_user   nom de l'utilisateur mysql a creer
	-p  mysql_pass   mot de passe mysql
	-b  mysql_base   nom de la base de donnees mysql
	-q  mysql_nb	   nombre de bases de donnees a creer
	-m  mail_respons mail du responsable du site
	-a	creer_awstats activer les statistiques awstats
#	-i  init_mutu	 lancer le script de creation d'une instance de mutu de SPIP

	NOTE: vous devez etre superutilisateur pour faire tourner ce script.
	ATTENTION!: ce script contient des inforamtions sensibles.  Evitez de le rendre lisible par tous.
-EOF-
}


function root_check
{
	#####
	#	Function to check if user is root
	#	No arguments
	#####

	if [ "$(id | sed 's/uid=\([0-9]*\).*/\1/')" != "0" ]; then
		error_exit "Vous devez etre superutilisateur pour faire tourner ce script."
	fi
}


function cree_awstats()
{
#	Fonction pour creer et configurer les répertoires et fichiers de conf 
#	nécessaires pour qu'awstatst tourne sur http://nom-domaine.tld/awstats
#	avec un accès restreint pour l'user+pass unix
#		3 arguments: $1 le nom de domaine, $2 login unix, $3 pass unix  

    #apache doit pouvoir mettre a jour les logs pour awstats update en cron qui vide les logs
      touch ${REP_VHOSTS}/$1/logs/access_log
#a tester mais en principe les 2 lignes suivantes sont pas obligés si appel de cette fct dans le process de crea de vhost...
    chown root:$USER_APACHE ${REP_VHOSTS}/$1/logs/access_log
	  chmod  755 ${REP_VHOSTS}/$1/logs/access_log
	#créer le fichier de conf et l'user + pass  
	  sed "s/nom_domaine.tld/$1/g" awstats.nom_domaine.tld.conf > ${REP_AWSTATS_CONF}/awstats.$1.conf
	  chmod 644 ${REP_AWSTATS_CONF}/awstats.$1.conf
	  htpasswd -b ${REP_AWSTATS_CONF}/users.pwd $2 $3
}


#	-------------------------------------------------------------------
#	Program starts here
#	-------------------------------------------------------------------

##### Initialization And Setup #####

# Set file creation mask so that all files are created with 600 permissions.

umask 066
root_check

# Trap TERM, HUP, and INT signals and properly exit

trap "signal_exit TERM" TERM HUP
trap "signal_exit INT"  INT

# Create temporary file(s)
#make_temp_files


##### Command Line Processing #####

if [ "$1" = "--help" ]; then
	helptext
	graceful_exit
fi


#les parametres ayant une valeur par defaut
numero_defaut=999
mysql_nb_defaut=1
mysql_nb_defaut=1
# pour les mots de passe on genere un pass a 10 caracteres aleatoire pour la valeur par defaut
unix_pass_defaut=`< /dev/urandom tr -dc _A-Z-a-z-0-9 | head -c10`
mysql_pass_defaut=`< /dev/urandom tr -dc _A-Z-a-z-0-9 | head -c10`

#les parametres dependants des applis installes
creer_awstats_defaut=non
init_mutu_defaut=non



#recuperation des valeurs passees par la ligne de commande
while getopts ":hd:n:u:x:s:p:b:q:m:i:a:" opt; do
	case $opt in
		d )	ndd=$OPTARG;;
		n )	numero=$OPTARG;;
		u )	unix_user=$OPTARG;;
		x )	unix_pass=$OPTARG;;
		s )	mysql_user=$OPTARG;;
		p )	mysql_pass=$OPTARG;;
		b )	mysql_base=$OPTARG;;
		q ) mysql_nb=$OPTARG;;
		m )	mail_respons=$OPTARG;;
#		i ) init_mutu=$OPTARG;;
		a ) creer_awstats=$OPTARG;;

		h )	helptext
			graceful_exit ;;
		* )	usage
			clean_up
			exit 1
	esac
done

#saisie interactive des parametres absents de la ligne de commande
if [ -z $ndd ]; then
	echo -n "Nom de domaine: "
    read reponse
    if [ -n "$reponse" ]; then
        ndd=$reponse
	else
		error_exit "erreur: il manque le parametre ndd (-d nom-de-domaine.tld)"
    fi	
fi
if [ -z $numero ]; then
	echo -n "Numero du vhost [$numero_defaut]: "
    read reponse
    if [ -n "$reponse" ]; then
        numero=$reponse
    else
    	numero=$numero_defaut
    fi	
fi
if [ -z $unix_user ]; then
	echo -n "Login du compte unix: "
    read reponse
    if [ -n "$reponse" ]; then
        unix_user=$reponse
	else
		error_exit "erreur: il manque le parametre unix_user (-u login_utilisateur)"
	fi
fi
if [ -z $unix_pass ]; then
	echo -n "Mot de passe du compte unix [$unix_pass_defaut]: "
    read reponse
    if [ -n "$reponse" ]; then
        unix_pass=$reponse
    else
    	unix_pass=$unix_pass_defaut
    fi	
fi
if [ -z $mysql_user ]; then
	echo -n "Login du compte MySQL [${unix_user}_php]: "
    read reponse
    if [ -n "$reponse" ]; then
        mysql_user=$reponse
	else
	 	mysql_user=$unix_user'_php'
	fi
fi
if [ -z $mysql_pass ]; then
	echo -n "Mot de passe du compte MySQL [$mysql_pass_defaut]: "
    read reponse
    if [ -n "$reponse" ]; then
        mysql_pass=$reponse
    else
    	mysql_pass=$mysql_pass_defaut
    fi	
fi
if [ -z $mysql_base ]; then
	echo -n "Entrez le prefixe des bases mysql [$unix_user]: "
    read reponse
    if [ -n "$reponse" ]; then
        mysql_base=$reponse
	else
	 	mysql_base=$unix_user
	fi
fi
if [ -z $mysql_nb ]; then
	echo -n "Nombre de bases MySQL [$mysql_nb_defaut]: "
    read reponse
    if [ -n "$reponse" ]; then
        mysql_nb=$reponse
    else
    	mysql_nb=$mysql_nb_defaut
    fi	
fi
# si plusieurs bases demandees ajouter le _ a la fin de $mysql_base
if [ $mysql_nb != 1 ]; then
  mysql_base=$mysql_base'_'
fi
if [ -z $mail_respons ]; then
	echo -n "Mail du responsable du domaine [${unix_user}@$ndd]: "
    read reponse
    if [ -n "$reponse" ]; then
        mail_respons=$reponse
	else
	 	mail_respons=$unix_user'@'$ndd
	fi
fi
if [ -z $creer_awstats ]; then
	echo -n "Activer awstats pour ce domaine (oui|non)) [$creer_awstats_defaut]: "
    read reponse
    if [ -n "$reponse" ]; then
        creer_awstats=$reponse
    else
    	creer_awstats=$creer_awstats_defaut
    fi	
fi
#if [ -z $init_mutu ]; then
#	echo -n "Creer une instance de mutu de SPIP (oui|non)) [$init_mutu_defaut]: "
#    read reponse
#    if [ -n "$reponse" ]; then
#        init_mutu=$reponse
#    else
#    	init_mutu=$init_mutu_defaut
#    fi	
#fi

#verification des parametres
  echo "$0 lance avec les parametres suivants: " 
	echo "ndd=           $ndd" 
 	echo "numero=        $numero" 
 	echo "unix_user=     $unix_user" 
 	echo "unix_pass=     $unix_pass" 
	echo "mysql_user=    $mysql_user" 
	echo "mysql_pass=    $mysql_pass" 
	echo "mysql_base=    $mysql_base" 
  echo "mysql_nb=      $mysql_nb"
	echo "mail_respons=  $mail_respons"
	echo "crer_awstats=	 $creer_awstats"
#	echo "init_mutu=	 $init_mutu"
	echo -n "Lancer la creation du vhost? (oui|non) [oui]: "
  read reponse
  if [[ $reponse = "non" ]]; then
      error_exit "Abandon par l'utilisateur"
  fi	
  	
#graceful_exit

  	
# creer l'unix_user
	# verifier que le compte n'existe pas deja
	if ! grep -q -w $unix_user /etc/passwd ; then
		#recup le mot de passe crypte
		mdp_crypt=$(php -f mdp.php -- $unix_pass)
		#creation du compte
		useradd -d ${REP_VHOSTS}/$ndd -m -g users -s /bin/bash -p $mdp_crypt $unix_user
	else
		if [ ! -d ${REP_VHOSTS}/$ndd ]; then
			mkdir ${REP_VHOSTS}/$ndd
		fi
	fi


# creation du vhost
	#creer le fichier de conf du vhost a partir du modele 0X_nom_domaine.tld.conf
	#on utilise sed pour generer la copie avec remplacements des nom_domaine.tld par la valeur passee en param -d
  #pour remplacement des parametres du serveur par les constantes
if [ ! -f $REP_STOCKAGE/$numero"_"$ndd.conf ]; then
	sed -e "s/nom_domaine.tld/$ndd/g" \
    -e "s/rep_vhost/$REP_VHOSTS_ECHAP/g" \
    -e "s/ip_serveur/$IP_SERVEUR/g" \
    -e "s/mail_serveur_admin/$MAIL_SERVEUR_ADMIN/g" 0X_nom_domaine.tld.conf >$REP_STOCKAGE/$numero"_"$ndd.conf
 	cp $REP_STOCKAGE/$numero"_"$ndd.conf ${REP_APACHE_CONF}/$numero"_"$ndd.conf
 	chmod 0644 ${REP_APACHE_CONF}/$numero"_"$ndd.conf
fi

	
# creation de l'arborescence de rep du vhost a partir du modele + mettre le bon proprio & droits
if [ ! -d ${REP_VHOSTS}/$ndd/html ]; then
	cp -R sous-dom.domaine.tld/* ${REP_VHOSTS}/$ndd
	chown -R $unix_user:$USER_APACHE ${REP_VHOSTS}/$ndd
	chmod -R 2750 ${REP_VHOSTS}/$ndd
	chmod -R g+s ${REP_VHOSTS}/$ndd/html
	
  #par defaut les repertoires de logs appartiennent a root
    chown -R root:$USER_APACHE ${REP_VHOSTS}/$ndd/logs
    chmod -R 2750 ${REP_VHOSTS}/$ndd/logs

  #creer l'instance awstats si necessaire
	if [[ $creer_awstats = "oui" ]]; then
		cree_awstats $ndd $unix_user $unix_pass
	fi
	
  #pour les reps utilises par d'autres applis passer en 770
	chmod 770 ${REP_VHOSTS}/$ndd/awstats  ${REP_VHOSTS}/$ndd/tmp
	
  #ajouter le lien symbolique pour phpmyadmin
#	ln -s $CHEMIN_PHPMYADMIN ${REP_VHOSTS}/$ndd/html
fi


##### Bases MySQL: generer le fichier de commandes MySQL puis le jouer #####

#les fonctions qui generent les commandes mysql dynamiquement

function cree_user()
{
  	echo REPLACE INTO mysql.user \(Host ,User ,Password, ssl_cipher, x509_issuer, x509_subject\) VALUES \(\'localhost\', \'"$mysql_user"\', PASSWORD\(\'"$mysql_pass"\'\), '""','""','""' \)\;
}

function cree_base()
{
#	if [ -z $1 ]; then
  		echo CREATE DATABASE IF NOT EXISTS $mysql_base$1 \;
#	else
#		echo CREATE DATABASE IF NOT EXISTS $mysql_base \;
#	fi
	echo REPLACE INTO mysql.db \(
  	echo         Host,Db,User,
  	echo         Select_priv,Insert_priv,Update_priv,Delete_priv,
  	echo         Create_priv,Drop_priv,Grant_priv,References_priv,Index_priv,
  	echo         Alter_priv,Create_tmp_table_priv,Lock_tables_priv,Create_view_priv,
  	echo         Show_view_priv,Create_routine_priv,Alter_routine_priv,Execute_priv
  	echo       \)
  	echo       VALUES \(
  	echo         \'localhost\', \'"$mysql_base$1"\',\'"$mysql_user"\', 
  	echo         \'Y\', \'Y\', \'Y\', \'Y\', \'Y\', \'Y\', \'N\', \'Y\', \'Y\', \'Y\', \'Y\', \'Y\', \'Y\', \'Y\', \'Y\', \'Y\', \'Y\'
  	echo       \)\;
}

function flush_privileges
{
  	echo FLUSH PRIVILEGES\;
  	echo "exit"
}

#maintenant qu'on a les fonctions, preparer le fichier toto.sql
#creation de l'user MySQL
  cree_user > toto.sql

#creation + autorisation acces d'autant de bases que necessaire
  for ((i=1; i <= mysql_nb ; i++))
#for i in 1 2 3  #version de test pour win-bash
  do
  	 if [ $mysql_nb != 1 ]; then
          cree_base $i >> toto.sql
          plur=s
      else
          cree_base >> toto.sql
          plur=""
      fi
  done

#recharger les privileges pour que les modifs prennent effet
  flush_privileges >> toto.sql

#lancer le fichier de commandes MySQL: toto.sql: 
  mysql -u $USER_MYSQL --password=$PASS_MYSQL mysql < toto.sql


##### le memo #####
#creer le fichier txt avec tous les parametres pour envoi par mail
function creer_memo()
{
	echo '-----------------------------------------------------------------------'
  	echo Parametres de l\'hebergement pour http\://$ndd
	echo " "
	echo mail responsable\: $mail_respons
	echo " "
	echo acces par FTP\: sftp\://$ndd
	echo \(attention\! il faut etre en protocole SFTP\!\)
	echo compte utilisateur\: $unix_user
	echo mot de passe\: $unix_pass
  echo port\: 2222
	echo connexion SSH egalement possible avec ce compte
	echo \(sous Windows utilisez PuttY et/ou WinSCP\) 
	echo " "
	if [[ $creer_awstats = "oui" ]]; then
		echo statistiques des visites disponibles sur http\://$ndd/awstats
		echo \(identifiant et passe sont ceux du compte utilisateur\)
		echo " "
	fi
	echo $mysql_nb base$plur de donnees MySQL
	echo compte utilisateur MySQL\: $mysql_user
	echo mot de passe\: $mysql_pass
	echo host \(pour connexion PHP\)\: localhost
	for ((i=1; i <= mysql_nb ; i++))
# for i in 1 2 3  #version de test pour win-bash
	do
	    if [ $mysql_nb != 1 ]; then
          echo base $i\: $mysql_base$i
      else
          echo base\: $mysql_base
      fi
	done
	echo acces PHPmyadmin\: http\://$ndd/phpmyadmin 
	echo \(alias de $URL_PHPMYADMIN\)
	echo " "
	echo '-----------------------------------------------------------------------'
}

  creer_memo > $REP_STOCKAGE/memo"_"$numero"_"$ndd.txt


##### creation du SPIP mutu si necessaire #####
    if [[ $init_mutu = "oui" ]]; then
    	echo Lancement du script de creation du SPIP mutu
		  if [ $mysql_nb != 1 ]; then
        	${CHEMIN_CREE_SPIP}/creer_spip.sh -d $ndd -u $unix_user -s $mysql_user -p $mysql_pass -b $mysql_base"1" -g oui
    	else
    		${CHEMIN_CREE_SPIP}/creer_spip.sh -d $ndd -u $unix_user -s $mysql_user -p $mysql_pass -b $mysql_base -g oui
    	fi
    fi


##### finitions, nettoyage et sortie propre #####
  chown -R $USER_STOCKAGE $REP_STOCKAGE/
  rm toto.sql

    
#recharger la conf d'apache pour valider le nouveau vhost
if ( /etc/init.d/apache2 reload ); then 
  graceful_exit
fi

