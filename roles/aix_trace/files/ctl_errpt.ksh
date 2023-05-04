# UJM 05/2020
# Controle errpt
# UJM 2021-11-10 exclusion des messages infos liés au reboot AIX 7.2 (arpege boot ts les soirs)


DIR_LOG=/var/isaaix/logs
SCRIPT=`basename $0`

# Pour le errpt, le format est: mmddhhmmyy  
DATEERRPT=`date +%m%d0000%y`
LIBEERRPT="quotidien"

LPAR=`hostname`
SSAAMMJJ=`date +%Y%m%d`
LANG=C		# Pour les LPAR francaises


OPtt=""
OPdebug=""
OPverbeux=""
OPserveur=""
OPexclu=""




# Anomalies
KO_fct()
{
$OPdebug
CR=$1
shift 1
echo "\n!!! KO:$CR " `date +%y%m%d_%H:%M` $*
}

# Message OK
OK_fct()
{
LIBELLE="$1"
shift 1
echo "#   $LIBELLE:" `date +%y%m%d_%H:%M` $*
}

#
# Message OK a l'ecran uniquemnet si mode verbeux
OKvbx_fct()
{
$OPdebug
LIBELLE="$1"
shift 1
[ "$OPverbeux" = "YES" ] && echo "#   $LIBELLE:" `date +%y%m%d_%H:%M` "$*"
}


# Erreur grave, message d'ano et EXIT
EXIT_fct()
{
$OPdebug
CR=$1
shift 1
echo "\n!!! KO:$CR " `date +%y%m%d_%H:%M` $*   
rm -f ${DIR_LOG}/${SCRIPT}.$$.*
exit $CR
}



##################
# Aide
menu_fct()
{
$OPdebug
echo "\n\nUtilisation de $SCRIPT"
echo ""
echo "Faire $SCRIPT [-d] [-v] [-e A924A5FC,A0000001,A0000002] "
echo ''
echo ' -x         L option -x est facultative'
echo '            Signale s il y a des erreurs en errpt'
echo ' -m         Les erreurs du mois en cours'
echo '            Par défaut, du jour uniquement'
echo ''
echo " -e         Exclusions supplémentaires facultatives"
echo "            Suivant le contexte certaines erreurs ne sont pas à signaler"
echo "            Si plusieurs exclusions les séparer par ,"
echo "            A924A5FC=SOFTWARE PROGRAM ABNORMALLY TERMINATED"
echo "            A0000001=Pour exemple"
echo ''
echo ' -d debug'
echo ' -v verbeux'
echo ''
}



# ---------------------
# Controle errpt
# ---------------------
ctl_errpt()
{
$OPdebug
DEBUG=ctl_errpt
OK_fct info Controle errpt "($LIBEERRPT)" de $LPAR

# Ujm: Initiallement les type=INFO étaient exclus
# Cependant des messages tel que 7FA22C9 UNABLE TO ALLOCATE SPACE IN FILE SYSTEM sont classés INFO
# Du coupe on prend tout et on exclu au fur et a mesure les fausses erreurs
TYPE="PEND,PERF,PERM,TEMP,INFO"      		#==> TYPE errpt = INFO pas pris
EXCLUfixe="192AC071,A5E6DB96,08917DC6,2BFA76F6,9DBCFDEE,A6DF45AA,AA8AB241,D221BD55,0873CF9F,DE84C4DB,D1E21BA3,3CACA614,69350832,159D686C,F2646817"

# Détail des exclusions
# IDENTIFIER TIMESTAMP  T C RESOURCE_NAME  DESCRIPTION
# A5E6DB96   0518141620 I S pmig           Client Partition Migration Completed
# 08917DC6   0518141520 I S pmig           Client Partition Migration Started
# 0873CF9F   0420175221 T S pts/5          TTYHOG OVER-RUN
# AA8AB241   0419210621 T O OPERATOR       OPERATOR NOTIFICATION
# D1E21BA3   0424165621 I S errdemon       LOG FILE EXPANDED TO REQUESTED SIZE
# Ajout 7200-05-04-2220
# 159D686C   1107101722 I S pmig           Client Partition Migration Completed
# F2646817   1107101722 I S pmig           Client Partition Migration Started




# Ujm 20/04/2021: Lié au reboot
# 2BFA76F6   0419210421 T S SYSPROC        SYSTEM SHUTDOWN BY USER
# 9DBCFDEE   0419210521 T O errdemon       ERROR LOGGING TURNED ON
# 192AC071   0415113720 T O errdemon       ERROR LOGGING TURNED OFF
# A6DF45AA   0419210621 I O RMCdaemon      The daemon is started.
# D221BD55   0419210521 I O perftune       RESTRICTED TUNABLES MODIFIED AT REBOOT
# DE84C4DB   0421100921 I O ConfigRM       IBM.ConfigRM daemon has started. 
# Ujm Ajout AIX 7.2 tj lié au boot
# 3CACA614   1109210521 I O sys0           Partition boot reason.
# 69350832   1109210521 T S SYSPROC        SYSTEM SHUTDOWN BY USER


if [ -s "$OpEXCLU" ]
then EXCLU=$EXCLUfixe
else EXCLU="$EXCLUfixe,$OpEXCLU"
fi


# On ne signale que les erreurs jour j ($DATEERRPT), en excluant les erreurs pas significatives
CMD="errpt -T $TYPE -k $EXCLU -s $DATEERRPT"
NB=`$CMD|grep -v ^IDENTIFIER |wc -l`
if [ "$NB" -ne 0 ] 
then  $CMD
      UNAME_F=`uname -F`
      SERVEUR=`grep $UNAME_F /usr/local/isaaix/psi/config.lst|awk '{print $2}'`
      EXIT_fct 201 $LPAR sur $SERVEUR $NB erreurs errpt à voir !!!
fi
OK_fct info Controle errpt de $LPAR OK
[ "$OPverbeux" = "YES" ] && errpt  -s $DATEERRPT 
exit 0

}




#######################################
## MAIN
#######################################



while getopts xvdhme: option
do
        case $option in
                v) OPverbeux=YES ;;
                d) OPdebug="set -x" ;;
		m) DATEERRPT=`date +%m010000%y`
		   LIBEERRPT="mensuel" ;;
		e) OpEXCLU=$OPTARG 
		   ;;
                x|h) [ -z "$OPtt" ] || EXIT_fct 104 Options exclusives: "$OPtt / $option"
                   export OPtt=$option ;;
                *) EXIT_fct 100 Parametre inconnu $option ;;
        esac
done



$OPdebug


# OPtt facultatif 
[ -z "$OPtt" ] && OPtt="x"



#########################
# En FONCTIOn DES OPTIONs
#########################
case "$OPtt" in
        x) ctl_errpt  ;;
        h) menu_fct ;;
        *) EXIT_fct 100 Parametre de traitement inconnu. $OPtt ;;
esac

