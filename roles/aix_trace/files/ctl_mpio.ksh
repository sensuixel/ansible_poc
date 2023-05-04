#! /bin/ksh
#  UJm 2018/06
# Signale les anomalies MPIO

# UJm 2019/06/04 LPAR Esvres en FR, Message FR/Anglais
# UJm 2019/09/13 MPIO 4FC en PSI pour prod et non 8 (pas de GAD)

# ujm 2020/02 Je verifie rw_max_time=0, sinon erreur
# IJ22714 - Possible undetected data corruption when disk attribute rw_max_time is non-zero
# ujm 2021/04/14-15 Adaptations pour Pure
# ujm 2021/07/27-28 Adaptations hdisk proxy commvault
# ujm 2021/11/09    Option -a pour tous les LUN
# ujm 2022/02/07 axgpr011 rajouté aux LPAR non aix 5.3
# ujm 2022/03/07 Pilote PURE pour AIX 5.3
# ujm 2022/08/16 Nbre de FC=1 si intellisnap PURE


export LANG=C

##################
# Aide
menu_fct()
{
echo "\n\nUtilisation de $0"
echo ""
echo "Faire $0 [-v] [a] "
echo ''
echo '   -v	verbeux, par defaut ne liste pas les VG/disques ok'
echo '   -a	all, y compris les disques ides VG pas actifs (none, alt_rootvg,...)'
echo ''
echo 'Signale les anomalies LSMPIO et les bests practices pas en place'
echo '(queue_depth=16, algorith=round shortest,... si AIX 7)'
echo '(queue_depth=8, algorith=round robin,... si AIX 5.3)'
echo '(queue_depth=8, algorith=round robin,.. pour les exceptions Globale/wpar et LPAR temporairement en erreur )'
echo ''
echo 'Par défaut, ne controle que les hdisk des VG activés'
echo 'Les anomalies sur le disque de service, clone et autres ne sont pas signalés'
echo 'Mettre -a si besoin de controller tous les hdisks'
echo ''
echo''

}

##################
# Message OK et KO

# Anomalies
KO_fct()
{
CR=$1
shift 1
echo "\n!!! KO:$CR " `date +%y%m%d_%H:%M` $*
exit $CR
}

# Message OK
OK_fct()
{
LIBELLE="$1"
shift 1
echo "### $LIBELLE:" `date +%y%m%d_%H:%M` $* 
}



########################################################################################
# Pour les AIX 6.1 7.1 et 7.2
# On utilise lsmpio vs lspath qui permet en+ de voir les dsk utilsés (pas uniquement enabled)
# et donc si le round-robin est OK
# Idem, il y a plus d'options au niveau des hdisk/fcs/vg

ctl_mpio7_fct()
{
$OPdebug

OK_fct $HOST "Controle MPIO '(Liens FC, pilote HDS/Pure, GAD et atributs LUN)' en cours ..."
KODEVICE=""


# ==================================================================
# Signale les liens MPIO  absent AIX 71 ou mauvais attributs hdisks
# -----------------------------------------------------------------
# Le controle se fait HDISK par HDISK, 
# Selon option $OPactif uniquement pour les VG actifs, ou tous
# Le done de la boucle do est loin plus bas 
# ==================================================================

OPlibelle=active
[ "$OPactif" = "none" ] && OPlibelle=hdisk
for HD in `lspv -L|grep $OPlibelle |awk '{print $1}'|sort`
do
CRDEVICE=0
VG=`lspv -L|grep -w $HD|awk '{print $3}'`
PILOTE=`lscfg -l $HD|sed "s/^.*PURE/PURE/"|sed "s/^.*Hitachi/Hitachi/"`
PiloteHD=inconnu
echo $PILOTE | grep -qi Hitachi && PiloteHD=HDS
echo $PILOTE | grep -qi PURE    && PiloteHD=PURE

# Le nom des VG pour les sauvegardes intellisnap sont sous la forme  cv_1627073714
INTELLISNAP=""
echo $VG| egrep -q "^cv_[0-9]*" && INTELLISNAP="intellisnap"
# Ujm 18/08/2022 Trap des intellisnap, parfois 1 FC, parfois 4
if [ ! -z "$INTELLISNAP" ]
then DATE=`date +%Y%m%d`
     {
     echo "\n\n\n#  =============================================="
     echo "#  HD=$HD VG=$VG PiloteHD=$PiloteHD   "`date`
     CMD='lscfg -lhdisk\*'
     echo "\n#  $CMD "
     lscfg -lhdisk\*
     CMD="lsmpio -ar"
     echo "\n#  $CMD "
     $CMD
     CMD="lsmpio -are"
     echo "\n#  $CMD " 
     $CMD
     CMD="lsmpio"
     echo "\n#  $CMD "
     $CMD
     CMD="lsmpio -Sdl $HD"
     echo "\n#  $CMD "
     $CMD
     CMD="lsmpio -ql $HD"
     echo "\n#  $CMD " 
     $CMD
     } >>/var/isaaix/logs/ctl_mpio.ksh.$HD.$DATE 2>&1
     echo "#   Trace détaillée $HD sous /var/isaaix/logs/ctl_mpio.ksh.$HD.$DATE"
fi


# HDISK actif ou pas
HDactif=YES
lspv -L -l $HD >/dev/null 2>&1 || HDactif=NO


# Enabled/Se pour tous les paths des hdiskhs actifs
# Pour les HDISKS pas actifs, ds le cas l'option OPactif=none, on accepte "Enabled  Clo" ou "Enabled  Sel"
# ------------------------------------------------------------------------------------

if [ "$OPactif" = "none" -a "$HDactif" = "NO" ]
then KOFC=`lsmpio -l $HD | grep -v -e "Enabled  Clo" -e "Enabled  Sel" | grep -v -c -e ^name -e "^$"`
     if [ "$KOFC" -ne 0 ]
     then echo "!!! Attention: HDISK inactif $VG: $HD  Les liens FC ne sont pas Enabled/Clo"
          lsmpio -l $HD|grep -w $HD
          KODEVICE="$KODEVICE"+$HD
          CRDEVICE=1
     fi
else KOFC=`lsmpio -l $HD | grep -v "Enabled  Sel" | grep -v -c -e ^name -e "^$"`
     if [ "$KOFC" -ne 0 ]
     then echo "!!! Attention: Tous les liens FC ne sont pas Enabled/Se pour $VG: $HD"
          lsmpio -l $HD|grep -w $HD
          KODEVICE="$KODEVICE"+$HD
          CRDEVICE=1
     fi 
fi



# Paramétres suivant le pilote
# ----------------------------
case $PiloteHD in
HDS)  Attr_algorithm="round_robin"
      Attr_queue_depth="16"
      Attr_reserve_policy="no_reserve"
      Attr_hcheck_interval=60
      ;;
PURE) Attr_algorithm="shortest_queue"
      Attr_queue_depth="16"
      Attr_reserve_policy="no_reserve"
      Attr_hcheck_interval=10
      ;;
*)   Attr_algorithm="inconnu"
     Attr_queue_depth="inconnu"
     Attr_reserve_policy="inconnu"
     Attr_hcheck_interval="inconnu"
     echo "!!! Attention: $HD VG=$VG Pilote GDS pas en place: " `lsdev -l $HD`
     KODEVICE="$KODEVICE"+$HD
     CRDEVICE=1
     ;;
esac



# Controle des Attribut des HDISK  AIX 7
# ---------------------------------------

OPT=`lsattr -El $HD -a algorithm|awk '{print $2}'`
if [ ! "$OPT" = "$Attr_algorithm" ]
then echo "!!! Attention: $HD Pilote $PiloteHD attribut algorithm=$OPT different de $Attr_algorithm"
     KODEVICE="$KODEVICE"+$HD
     CRDEVICE=1
fi

OPT=`lsattr -El $HD -a queue_depth|awk '{print $2}'`
if [ ! "$OPT" = "$Attr_queue_depth" ]
then echo "!!! Attention: $HD Pilote $PiloteHD attribut queue_depth=$OPT different de $Attr_queue_depth"
     KODEVICE="$KODEVICE"+$HD
     CRDEVICE=1
fi

OPT=`lsattr -El $HD -a reserve_policy|awk '{print $2}'`
if [ ! "$OPT" = "$Attr_reserve_policy" ]
then echo "!!! Attention: $HD Pilote $PiloteHD attribut reserve_policy=$OPT different de $Attr_reserve_policy"
     KODEVICE="$KODEVICE"+$HD
     CRDEVICE=1
fi

OPT=`lsattr -El $HD -a hcheck_interval|awk '{print $2}'`
if [ ! "$OPT" = "$Attr_hcheck_interval" ]
then echo "!!! Attention: $HD Pilote $PiloteHD attribut hcheck_interval=$OPT different de $Attr_hcheck_interval"
     KODEVICE="$KODEVICE"+$HD
     CRDEVICE=1
fi



# ujm 2020/02 Je verifie rw_max_time=0 (Que certains AIX d ou le 2>/dev/null ), sinon erreur
# IJ22714 - Possible undetected data corruption when disk attribute rw_max_time is non-zero
OPT=`lsattr -El $HD -a rw_max_time 2>/dev/null |awk '{print $2}'`
# Si rw_max_time absent je mets 0
[ $? -ne 0 ] && OPT=0
if [ "$OPT" -ne 0 ]
then echo "!!! Attention: $HD attribut rw_max_time doit etre 0 IJ22714 data corruption rw_max_time=$OPT"
     KODEVICE="$KODEVICE"+$HD
     CRDEVICE=1
fi



# Controle des FC du hdisk
# ------------------------
# Nbre de FC=1 ou 4 si intellisnap PURE
NBFC=`lsmpio -l $HD|grep -c hdisk`
if [ ! -z "$INTELLISNAP" ]
then if [  ! "$NBFC" = "1" -a ! "$NBFC" = "4" ]
     then  echo "!!! Attention: $HD VG=$VG $INTELLISNAP nbre de lien ni 1 ni 4 Nbre FC=$NBFC"
           KODEVICE="$KODEVICE"+$HD
           CRDEVICE=1
     fi
else if [  ! "$NBFC" = "4" -a ! "$NBFC" = "8" ]
     then  echo "!!! Attention: $HD VG=$VG nbre de lien ni 4 ni 8  Nbre FC=$NBFC"
         KODEVICE="$KODEVICE"+$HD
         CRDEVICE=1
     fi
fi


# Les Lpar prod doivent etre en GAD (8 fc) en zone nominale, et 4 en PSI
case `expr substr ${HOST} 1 2` in
        ap|as)          NBFCSTD=8 ;;
        *)              NBFCSTD=4 ;;
esac

# Cas des noms de LPAR prod ancien nommage, ou LPAR tests particulières
# ou cas particuliers hors-standard
case "$HOST" in
  rsinfo67|rsinfo68|rsprevbo|axgpr011|xi2821pp|xi2879pp|atcci069|ataai009|ataai003) NBFCSTD=8 ;;
esac


# 2021-04-15: 4 pour PURE hors-prod (sans doute 4 hors-prod et 8 prod)
# A la base : 8 pour PURE (sans doute 8 hors-prod et 16 prod)
[ "$PiloteHD" = "PURE" ] && NBFCSTD=4



# Pas de GAD en PSI
if [ -d /var/isaaix/psi ] 
then NBFCSTD=4
     PSI="Zone PSI"
else PSI=""
fi

# Ujm 16/08/2022
# En général 4, mais parfois 1 pour les hdisk intellisnap des sauvegardes proxy commvault
if [ -z "$INTELLISNAP" ] 
then if [ "$NBFC" = "$NBFCSTD" ]
     then  [ "$OPverbeux" = "YES" ] &&  echo "#     LPAR $HD Nb FC=" $NBFC " conforme " $PSI $INTELLISNAP
     else  echo "!!! Attention: $HD VG=$VG Pilote $PiloteHD Nbre FC=$NBFC au lieu de $NBFCSTD $PSI $INTELLISNAP"
           KODEVICE="$KODEVICE"+$HD
           CRDEVICE=1
     fi
else if [ "$NBFC" = "1" -o "$NBFC" = "4" ]
     then  [ "$OPverbeux" = "YES" ] &&  echo "#     LPAR $HD Nb FC=" $NBFC " conforme " $PSI $INTELLISNAP
     else echo "!!! Attention: $HD VG=$VG Pilote $PiloteHD Nbre FC=$NBFC au lieu de $NBFCSTD $PSI $INTELLISNAP"
           KODEVICE="$KODEVICE"+$HD
           CRDEVICE=1
     fi
fi



# Ujm 27/07/2021.  
# Les Hdisks proxy commvault (apaai006/07) sont particuliers, 
# Cpas de controle par rapport au nbr FC des autres hdisk 
if [ -z "$INTELLISNAP" ]
then case $PiloteHD in
     HDS)  [ -z "$NBFCREF_HDS" ] && NBFCREF_HDS=$NBFC
           if [ ! "$NBFC" = "$NBFCREF_HDS" ] 
           then echo "!!! Attention: $HD VG=$VG nbre de lien differents des autres disques de type $PiloteHD  Nbr "$NBFC"/"$NBFCREF"" 
               KODEVICE="$KODEVICE"+$HD
               CRDEVICE=1
           fi
           ;;
     PURE) [ -z "$NBFCREF_PURE" ] && NBFCREF_PURE=$NBFC 
           if [ ! "$NBFC" = "$NBFCREF_PURE" ]
           then echo "!!! Attention: $HD VG=$VG nbre de lien differents des autres disques de type $PiloteHD  Nbr "$NBFC"/"$NBFCREF_PURE""
               KODEVICE="$KODEVICE"+$HD
               CRDEVICE=1
           fi
           ;;
     *)   echo "!!! Attention: $HD VG=$VG Pilote GDS/Pure pas en place: " `lsdev -l $HD`
          KODEVICE="$KODEVICE"+$HD
          CRDEVICE=1
          ;;
     esac
fi


[ "$OPverbeux" = "YES" -a "$CRDEVICE" = "0" ] && echo "#     OK pour: $HD Pilote $PiloteHD sur $VG"
done



# Attribut des VG  AIX 7
# ----------------------
OK_fct $HOST Controle INFINITE RETRY des VG
CRDEVICE=0
for VG in `lspv -L |grep active |awk '{print $3}'|sort`
do
OPT=`lsvg -L $VG|grep "INFINITE RETRY"|sed "s/^.*INFINITE RETRY: *//"`
if [ ! "$OPT" = "yes" ]
then echo "!!! Attention: $VG attribut INFINITE RETRY=$OPT different de yes"
     KODEVICE="$KODEVICE"+$VG
     CRDEVICE=1
fi
[ "$OPverbeux" = "YES" -a "$CRDEVICE" = "0" ] && echo "#     OK pour INFINITE RETRY: $VG"
done




# Attribut des FC  AIX 7
# ----------------------
OK_fct $HOST Controle des attributs fcs
CRDEVICE=0
# Le dev/null est du fait des erreurs  pkcs11.
for FCS in `lsdev 2>/dev/null |grep ^fcs |awk '{print $1}'|sort`
do
OPT=`lsattr -El $FCS -a max_xfer_size|awk '{print $2}'`
if [ ! "$OPT" = "0x200000" ]
then echo "!!! Attention: $FCS attribut max_xfer_size=$OPT different de 0x200000"
     KODEVICE="$KODEVICE"+$FCS
     CRDEVICE=1
fi

OPT=`lsattr -El $FCS -a num_cmd_elems|awk '{print $2}'`
if [ ! "$OPT" = "256" ]
then echo "!!! Attention: $FCS attribut num_cmd_elems=$OPT different de 256"
     KODEVICE="$KODEVICE"+$FCS
     CRDEVICE=1
fi


[ "$OPverbeux" = "YES" -a "$CRDEVICE" = "0" ] && echo "#     OK pour: $FCS"
done






if [ -z "$KODEVICE"  ]
then  OK_fct $HOST Controle OK Liens/bests practices FC/LUN/VG OK
else  UNAME_F=`uname -F`
      SERVEUR=`grep $UNAME_F /usr/local/isaaix/psi/config.lst|awk '{print $2}'`
      KO_fct 121 $HOST sur $SERVEUR Liens FC/Hdisk/VG defectueux ou mal parametres pour $KODEVICE
fi

}
########################################################################################



########################################################################################
# Pour les AIX 5.3
# La commande lsmpio n 'existe pas, le pilote HDS hitachi n est pas a installer
# et les options hdisk fcs VG ... ne sont pas les mêmes
# Le controle est plus light
ctl_mpio5_fct()
{
$OPdebug

OK_fct $HOST "Controle des liens FC, pilote PURE ou other, GAD et attributs LUN AIX 5.3"
KODEVICE=""


# Signale les liens MPIO absent  AIX 53
# -------------------------------------
for HD in `lspv -L|grep -w active|awk '{print $1}'|sort`
do
CRDEVICE=0
VG=`lspv -L|grep -w $HD|awk '{print $3}'`

PILOTE=`lscfg -l $HD|sed "s/^.*PURE/PURE/"|sed "s/^.*Other/Other/"`
PiloteHD=inconnu
echo $PILOTE | grep -qi Other   && PiloteHD=Other
echo $PILOTE | grep -qi PURE    && PiloteHD=PURE



KOFC=`lspath -l $HD | grep -cv "^Enabled" `
if [ "$KOFC" -ne 0 ]
then echo "!!! Attention: Tous les liens FC ne sont pas Enabled pour $VG: $HD"
     lspath -l $HD|grep -w $HD
     KODEVICE="$KODEVICE"+$HD
     CRDEVICE=1
fi 

# Pour verifier que ts les hdisks ont le même nombre de fscsi, qui doit etre 4 ou 8 (prod)
NBFC=`lspath -l $HD|grep -c hdisk`
[ -z "$NBFCREF" ] && NBFCREF=$NBFC

if [ ! "$NBFC" = "$NBFCREF" ] 
then echo "!!! Attention: $HD nbre de lien differents des autres disques Nbr "$NBFC"/"$NBFCREF"" 
    KODEVICE="$KODEVICE"+$HD
    CRDEVICE=1
fi
if [  ! "$NBFC" = "4" -a ! "$NBFC" = "8" ]
then  echo "!!! Attention: $HD nbre de lien ni 4 ni 8  Nbre FC=$NBFC AIX 5.3"
    KODEVICE="$KODEVICE"+$HD
    CRDEVICE=1
fi

# Attribut des HDISK  AIX 53
# --------------------------
# 07/03/2022 Ujm Pilote PURE possible pour AIX 5.3


# Paramétres suivant le pilote
# ----------------------------
case $PiloteHD in
PURE) Attr_algorithm="round_robin"
      Attr_queue_depth="16"
      Attr_reserve_policy="no_reserve"
      Attr_hcheck_interval=10
      ;;
Other) Attr_algorithm="round_robin"
      Attr_queue_depth="8"
      Attr_reserve_policy="no_reserve"
      Attr_hcheck_interval=10
      ;;
*)   Attr_algorithm="inconnu"
     Attr_queue_depth="inconnu"
     Attr_reserve_policy="inconnu"
     Attr_hcheck_interval="inconnu"
     echo "!!! Attention: $HD VG=$VG Pilote GDS pas en place: " `lsdev -l $HD`
     KODEVICE="$KODEVICE"+$HD
     CRDEVICE=1
     ;;
esac



# Controle des Attribut des HDISK  AIX 5
# ---------------------------------------

OPT=`lsattr -El $HD -a algorithm|awk '{print $2}'`
if [ ! "$OPT" = "$Attr_algorithm" ]
then echo "!!! Attention: $HD Pilote $PiloteHD attribut algorithm=$OPT different de $Attr_algorithm"
     KODEVICE="$KODEVICE"+$HD
     CRDEVICE=1
fi

OPT=`lsattr -El $HD -a queue_depth|awk '{print $2}'`
if [ ! "$OPT" = "$Attr_queue_depth" ]
then echo "!!! Attention: $HD Pilote $PiloteHD attribut queue_depth=$OPT different de $Attr_queue_depth"
     KODEVICE="$KODEVICE"+$HD
     CRDEVICE=1
fi

OPT=`lsattr -El $HD -a reserve_policy|awk '{print $2}'`
if [ ! "$OPT" = "$Attr_reserve_policy" ]
then echo "!!! Attention: $HD Pilote $PiloteHD attribut reserve_policy=$OPT different de $Attr_reserve_policy"
     KODEVICE="$KODEVICE"+$HD
     CRDEVICE=1
fi

OPT=`lsattr -El $HD -a hcheck_interval|awk '{print $2}'`
if [ ! "$OPT" = "$Attr_hcheck_interval" ]
then echo "!!! Attention: $HD Pilote $PiloteHD attribut hcheck_interval=$OPT different de $Attr_hcheck_interval"
     KODEVICE="$KODEVICE"+$HD
     CRDEVICE=1
fi


[ "$OPverbeux" = "YES" -a "$CRDEVICE" = "0" ] && echo "#     OK pour: $HD Pilote $PiloteHD sur $VG"
done



# Pas de Infinite retry sur les VG AIX 53
# ---------------------------------------



# Attribut des FC  AIX 53
# -----------------------

OK_fct $HOST Controle des attributs fcs AIX 5.3
CRDEVICE=0
for FCS in `lsdev |grep ^fcs |awk '{print $1}'|sort`
do
OPT=`lsattr -El $FCS -a max_xfer_size|awk '{print $2}'`
if [ ! "$OPT" = "0x100000" ]
then echo "!!! Attention: $FCS attribut max_xfer_size=$OPT different de 0x200000"
     KODEVICE="$KODEVICE"+$FCS
     CRDEVICE=1
fi

OPT=`lsattr -El $FCS -a num_cmd_elems|awk '{print $2}'`
if [ ! "$OPT" = "200" ]
then echo "!!! Attention: $FCS attribut num_cmd_elems=$OPT different de 256"
     KODEVICE="$KODEVICE"+$FCS
     CRDEVICE=1
fi


[ "$OPverbeux" = "YES" -a "$CRDEVICE" = "0" ] && echo "#     OK pour: $FCS"
done



# Au final
# --------


if [ -z "$KODEVICE"  ]
then  OK_fct $HOST Controle des liens/bests practices FC/LUN/VG OK AIX 5.3
else  KO_fct 121 $HOST Liens FC/Hdisk/VG defectueux ou mal parametres pour $KODEVICE AIX 5.3
fi

}
########################################################################################






#######################################
## MAIN
#######################################


OPverbeux=""
OPdebug=""
OPtt=""
OPLUN=""
OPactif="active"


while getopts advh option
do
        case $option in
                v) export OPverbeux=YES 
		   ;;
                a) export OPactif=none 
		   ;;
                d) export OPdebug="set -x"
		   ;;
                h) [ -z "$OPtt" ] || KO_fct 104 Options exclusives: "$OPtt / $option"
                   export OPtt=$option
		   ;;
                *) KO_fct 100 Parametre inconnu $option
		   menu_fct
		   exit 1
		   ;;
        esac
done
$OPdebug

[ -z "$OPtt" ] && OPtt=x
[ -z "$OPverbeux" ] && OPverbeux="NO"

HOST=`hostname`
OS=`oslevel`


#########################
# En FONCTIOn DES OPTIONs
#########################

# Pour les WPAR, on ne peut pas mettre a jour le poilote HDS Globale aix 7.1, on reste aix 5.3
# Et il y a les oublies lors de la reloc a reprendre ultérieurement
case "$OPtt" in
	x)	if [ "$OS" = "5.3.0.0" ] 
                then ctl_mpio5_fct
                else case $HOST in
                       adcci051|adcci057) 
		        	OK_fct $HOST "Controle 5.3 du fait WPAR ou LPAR a reparametrer"
			        ctl_mpio5_fct ;;
                       *) 	ctl_mpio7_fct ;;
                      esac
                fi
                ;;
	h)   	menu_fct ;;	
	*) KO_fct 101 Parametre de traitement inconnu.  ;;
esac
