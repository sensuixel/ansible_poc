#! /bin/ksh
#  UJm 2018/10

# Signale les anomalies réseau (vlan,umask,gateway,dns,...)
# 2019/02/06 UJM Ajout des PAMunix
# 2019/06/04 UJM LPAR Esvres en FR, Message FR/Anglais
# 2021/10/14 UJM Changement des IP des DNS primaire et secondaire
# 2021/10/25 UJM Ordre des DNS Local si présent, Primaire=PA6 Secondaire=Chartres 
# 2022/04/08 UJM suppression ses anciennes DNS/NTP S1DNSold=10.57.127.5 S2DNSold=10.56.127.5
# 2022/10/03 CDE Suppression des VLAN plus utilisés.

export LANG=C
export SSAAMM=`date +%Y%m`




##################
# Aide
menu_fct()
{
echo "\n\nUtilisation de $0"
echo ""
echo "Faire $0 [-v] [-d]"
echo ''
echo '   -v	verbeux, par defaut ne liste pas les élements OK'
echo '   -d     debug (set -x)'
echo ''
echo 'Signale les configs réseau pas conformes, les bests practices pas en place'
echo 'Attention, on ne controle que les interfaces (en) activés'
echo 'Les en ent down ne sont pas verifies, uniquement signales present en mode verbeux'
echo ''
echo''

}


# TABLEAU des RESEAUX
netwkork_lst()
{
cat <<FIN

# Utiliser pour verifier les @ip et la configuration réseau
# En particulier lors de la reloc Chartres -> Pa6 pour reconstruire l'interface nominal

# Format de la Ligne
# # en debut de ligne= commentaire
# Tous les champs sont obligatoires, le separateur est OBLIGATOIREMENT ESPACE
# les grep se font sous la forme grep " valeur" afin de ne pas tomber sur une auter ligne

# Les neants sont ceux qui n ont pas lieu d etre  (pas de valeur, ou la valeur ne doit pas etre utilisée)
# Les absents sont les non renseignes (inconnus)

# ---------------------------------------------------------------------------------------------------
# VLAN	IPnetwork      Gateway	      Netmask         Netmask    MTU    Site            Usage
# 	(netstat -in)				    Format /xx	        Origine
# ---------------------------------------------------------------------------------------------------
200    10.200          10.200.0.1     255.255.0.0        16      1500   Chartres        Prod
202    10.202          10.202.0.1     255.255.0.0        16      1500   Chartres        Hors-prod
320    10.220.128      10.220.128.1   255.255.128.0      17      1500   Mons            Prod
403    172.21.10       172.21.10.1    255.255.255.0      24      1500   Esvres          Prod
411    172.21.18       172.21.18.1    255.255.255.0      24      1500   Esvres          Hors-prod
1501   10.55           10.55.0.1      255.255.252.0      22      1500   Aubervilliers   Prod
1510   10.55.109       10.55.109.1    255.255.255.128    25      1500   Aubervilliers   ADMIN_OOB
1511   10.55.32        10.55.32.1     255.255.252.0      22      1500   Aubervilliers   Hors-prod
1512   10.55.36        10.55.36.1     255.255.252.0      22      1500   Aubervilliers   TEST
2802   10.57.2         10.57.2.1      255.255.254.0      23      1500   Mons            Prod
2812   10.57.10        10.57.10.1     255.255.254.0      23      1500   Mons            Hors-prod
2901   10.56           10.56.0.1      255.255.254.0      23      1500   Chartres        Prod
2911   10.56.8         10.56.8.1      255.255.254.0      23      1500   Chartres        Hors-prod
# CDE 03/10/2022 VLAN plus utilisés
# 2801   10.57           10.57.0.1      255.255.254.0      23      1500   Mons            Prod
# 2902   10.56.2         10.56.2.1      255.255.254.0      23      1500   Chartres        Prod
# 3100   10.210          10.210.0.1     255.255.128.0      25      1500   Chartres        Prod
# 2811   10.57.8         10.57.8.1      255.255.254.0      23      1500   Mons            Hors-prod
# 2912   10.56.10        10.56.10.1     255.255.254.0      23      1500   Chartres        Hors-prod
# 3102   10.211.1        10.211.1.1     255.255.255.128    25      1500   Chartres        Hors-prod
# ---------------------------------------------------------------------------------------------------
# Le reseau de backup 4050 dispose dune gateway 172.16.48.1 mais uniquement pour accéder a 
# la zone backup de la seconde zone PA6
# Donc volontairement mis neant" car ne doit pas etre ulisé pour AIX
4050   172.16.48       neant          255.255.252.0      22      9000   Aubervilliers   BACKUP
# ---------------------------------------------------------------------------------------------------
# Spécifique PSI
40     10.110.40       10.110.40.1    255.255.255.0      24      1500   Aubervilliers   PSI
56     10.110.56       10.110.56.1    255.255.255.0      24      1500   PSI-Chartres    PSI
# Attention les VLAN 3195 et 3196 ont des plages IP différentes entre PROD et PSI
# Ci-dessous les valeurs en zone PROD
3195   10.128.128      neant          255.255.255.0      24      1500   Aubervilliers   HMC
3196   10.255.255      neant          255.255.255.0      24      1500   Aubervilliers   HMC

FIN
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
# Controle du réseau

ctl_lan_fct()
{
$DEBUG


OK_fct $HOST Controle du reseau en cours ...
KOLIST_NOM=""
KOLIST_BCK=""
CRIP=0

# On a déduit le nom de la LPAR d' apres hostname
# LPAR_NOM=nom nominal et LPAR_BCK=nom reseau backup
# Tous les attrributs (umask, ip, network, interface, ...) sont suffixés par _NOM ou _BCK suivant le reseau

# A partir des LPAR_NOM LPAR_BCK on verifie que le config reseau est conforme
# Gateway, umask, vlan , /etc/hosts, /etc/netsvc, DNS, ...


# ------------------------------------------------------------
# Verification /etc/hosts
# ----------------------
# Recherche des IP de la LPAR
# IP Nominale
NB=`grep -v -e "^#" -e bck /etc/hosts|grep -c "${LPAR_NOM}" `
case "$NB" in
	1) IP_NOM=`grep -v -e "^#" -e bck /etc/hosts|grep "${LPAR_NOM}" |awk '{print $1}'`
           ;;
	*) echo "!!! Erreur /etc/hosts IP non determinable pour ${LPAR_NOM}"
           grep -v -e "^#" -e bck /etc/hosts| grep -i ${LPAR_NOM}
	   IP_NOM=00.00.00.00
           CRIP_NOM=1 ; KOLIST_NOM="$KOLIST_NOM+Ip Nominale (hosts)"
           ;;
esac


# IP Backup
NB=`grep -v -e "^#" /etc/hosts|grep -c "${LPAR_BCK}" `
case "$NB" in
        1) IP_BCK=`grep -v "^#" /etc/hosts|grep -w "${LPAR_BCK}" |awk '{print $1}'`
           ;;
        *) echo "!!! Erreur /etc/hosts IP non determinable pour ${LPAR_BCK}"
           grep -v -e "^#" /etc/hosts | grep  ${LPAR_BCK}
           IP_BCK=00.00.00.00
	   CRIP_BCK=1 ; KOLIST_BCK="$KOLIST_BCK+Ip backup (hosts)"
           ;;
esac

# Les loopback IPV4 et IPV6 doivent etre présentes
# ------------------------------------------------
NB=`grep -v "^#" /etc/hosts|grep "loopback *localhost" | grep -c "127.0.0.1" `
if [ "$NB" -ne 1 ]
then echo "!!! Erreur /etc/hosts loopback localhost IPV4 absente"
           CRIP_NOM=1 ; KOLIST_NOM="$KOLIST_NOM+loopbackIPV4"
fi
NB=`grep -v "^#" /etc/hosts|grep "loopback *localhost" | grep -c "::1" `
if [ "$NB" -ne 1 ]
then echo "!!! Erreur /etc/hosts loopback localhost IPV6 absente"
           CRIP_NOM=1 ; KOLIST_NOM="$KOLIST_NOM+loopbackIPV6"
fi




# ------------------------------------------------------------------
# Controle de la resolution de nom, Host et DNS doivent etre OK

# Resolution de nom
# -----------------
host "${LPAR_NOM}" | grep -q $IP_NOM
if [ $? -ne 0 ]
then echo "!!! Resolution KO  pour ${LPAR_NOM}"
     host "${LPAR_NOM}"
     CRIP_NOM=1 ; KOLIST_NOM="$KOLIST_NOM+Resolution Host"
else [ "$OPverbeux" = "YES" ] && echo "#     IP Nominale: "`host "${LPAR_NOM}"`
fi
LPAR_ALIAS=`host "${LPAR_NOM}" | sed "s/^.*Aliases: *//"`
[ -z "${LPAR_ALIAS}" ] || [ "$OPverbeux" = "YES" ] && echo "#     Alias de ${LPAR_NOM}: ${LPAR_ALIAS}"

host "${IP_NOM}" | grep -q $LPAR_NOM
if [ $? -ne 0 ]
then echo "!!! $HOST Resolution KO  pour ${IP_NOM}"
     host "${IP_NOM}"
     CRIP_NOM=1 ; KOLIST_NOM="$KOLIST_NOM+Resolution IP"
fi


host "${LPAR_BCK}" | grep -q $IP_BCK
if [ $? -ne 0 ]
then echo "!!! $HOST Resolution KO  pour ${LPAR_BCK}"
     host "${LPAR_BCK}"
     CRIP_BCK=1 ; KOLIST_BCK="$KOLIST_BCK+Resolution Host"
else [ "$OPverbeux" = "YES" ] && echo "#     IP Backup: "`host "${LPAR_BCK}"`
fi
host "${IP_BCK}" | grep -q $LPAR_BCK
if [ $? -ne 0 ]
then echo "!!! Resolution KO  pour ${IP_BCK}"
     host "${IP_BCK}"
     CRIP_BCK=1 ; KOLIST_BCK="$KOLIST_BCK+Resolution IP"
fi


# Parametrage DNS
# ---------------
# Que IPV4, DNS IPV6 ko, hosts=local,bind4
NB=`grep -v  "^#" /etc/netsvc.conf |grep -c "." `
grep ^hosts /etc/netsvc.conf| tr -d " " |grep -q "^hosts=local,bind4$"
if [ $? -eq 0 -a "$NB" = 1 ]
then continue
else echo "!!! /etc/netsvc.conf pas conforme \(hosts=local,bind4\)"
     CRIP_NOM=1 ; KOLIST_NOM="$KOLIST_NOM+netsvc.conf"
fi
DOMAINEOK="server.lan|unix.lan|gie.root.ad"
DOMAINE_NOM=`grep ^domain /etc/resolv.conf|awk '{print $2}'`
DOMAINE_BCK=server.lan
grep ^domain /etc/resolv.conf|egrep -q "$DOMAINEOK"
if [ $? -ne 0 ]
then echo "!!! /etc/resolv.conf: domain pas conforme $DOMAINE_NOM  \($DOMAINEOK\)"
     CRIP_NOM=1 ; KOLIST_NOM="$KOLIST_NOM+resolv.conf"
else [ "$OPverbeux" = "YES" ] && echo "#     Domaine $LPAR_NOM: $DOMAINE_NOM"
fi

# DNS Nslookup
# ------------
nslookup "${LPAR_NOM}" | grep -q "^Address: *${IP_NOM}"
if [ $? -ne 0 ]
then echo "!!! $HOST Resolution DNS KO  pour ${LPAR_NOM}"
     CRIP_NOM=1 ; KOLIST_NOM="$KOLIST_NOM+DNS"
fi
nslookup "${LPAR_BCK}" | grep -q "^Address: *${IP_BCK}"
if [ $? -ne 0 ]
then echo "!!! $HOST Resolution DNS KO  pour ${LPAR_BCK}"
     CRIP_BCK=1 ; KOLIST_BCK="$KOLIST_BCK+DNS"
fi

# Et DNS Nslookup REVERSE
# -----------------------
# 
# En principe server.lan
# On accepte ag2rprd.gie.net, avec reverse=unix.lan, particularité Chartres  Vlan 200 ...
# On accepte les alias pour arpege ${LPAR_ALIAS}  exemple: rstestbo est 172.21.18.113,  alias:   esvxet13

IP_REVERSE=`echo "${IP_NOM}" | awk 'BEGIN { FS = "." } {print $4"."$3"."$2"."$1 }'`
nslookup "${IP_NOM}" | grep -q  "^${IP_REVERSE}.* ${LPAR_NOM}.${DOMAINE_NOM}" 
if [ $? -ne 0 ]
then case "${DOMAINE_NOM}" in
     ag2rprd.gie.net)
          nslookup "${IP_NOM}" | grep -q "^${IP_REVERSE}.* ${LPAR_NOM}.unix.lan"
          if [ $? -ne 0 ]
          then echo "!!! $HOST Resolution Reverse DNS KO ag2rprd.gie.net  pour ${IP_NOM} et ${LPAR_NOM}.${DOMAINE_NOM}"
               CRIP_NOM=1 ; KOLIST_NOM="$KOLIST_NOM+Reverse DNS"
          else echo "#     DNS Reverse toléré  ${IP_NOM} pour ${LPAR_NOM}.${DOMAINE_NOM} et DNS=.unix.lan" 
          fi
          ;;
     *)   if [ -z "${LPAR_ALIAS}" ]
          then echo "!!! $HOST Resolution Reverse DNS KO pour ${IP_NOM} et ${LPAR_NOM}.${DOMAINE_NOM}"
               CRIP_NOM=1 ; KOLIST_NOM="$KOLIST_NOM+Reverse DNS"
          else nslookup "${IP_NOM}" | grep -q "^${IP_REVERSE}.* ${LPAR_ALIAS}.${DOMAINE_NOM}"
               if [ $? -ne 0 ]
               then echo "!!! $HOST Resolution Reverse DNS KO pour ${IP_NOM} et ${LPAR_NOM}.${DOMAINE_NOM} Alias=${LPAR_ALIAS}"
                    CRIP_NOM=1 ; KOLIST_NOM="$KOLIST_NOM+Reverse DNS"
               else echo "#     Pas de DNS Reverse sur ${LPAR_NOM} ALIAS toléré pour ${IP_NOM} et ${LPAR_ALIAS}.${DOMAINE_NOM}"
               fi
          fi
          ;;
     esac
else [ "$OPverbeux" = "YES" ] && echo "#     DNS Reverse OK ${IP_NOM} pour ${LPAR_NOM}.${DOMAINE_NOM}" 
fi

IP_REVERSE=`echo "${IP_BCK}"| awk 'BEGIN { FS = "." } {print $4"."$3"."$2"."$1 }'`
nslookup "${IP_BCK}" | grep -q "^${IP_REVERSE}.* ${LPAR_BCK}.${DOMAINE_BCK}"
if [ $? -ne 0 ]
then echo "!!! $HOST Resolution Reverse DNS bck KO  pour ${IP_BCK} et ${LPAR_BCK}.${DOMAINE_BCK}"
     CRIP_BCK=1 ; KOLIST_BCK="$KOLIST_BCK+Reverse DNS"
else [ "$OPverbeux" = "YES" ] && echo "#     DNS Reverse OK ${IP_BCK} pour ${LPAR_BCK}.${DOMAINE_BCK}" 
fi


# Serveur DNS
# -----------
# Doivent etre S1DNS et S2DNS, possibilite de S0DNS pour le service named
# Doublon interdit et si S0DNS doit etre présent et named.conf doit etre OK
S0DNSok=127.0.0.1
S1DNSok=10.55.127.5
S2DNSok=10.54.127.5


S0DNS_IP=absent
S1DNS_IP=absent
S2DNS_IP=absent

grep ^nameserver /etc/resolv.conf|grep -q $S0DNSok       && S0DNS_IP=$S0DNSok
grep ^nameserver /etc/resolv.conf|grep -q $S1DNSok       && S1DNS_IP=$S1DNSok 
grep ^nameserver /etc/resolv.conf|grep -q $S2DNSok       && S2DNS_IP=$S2DNSok 


# Que des DNS connues ?
ListeDNSKO=`grep ^nameserver /etc/resolv.conf|grep -v -e "$S0DNS_IP" -e "$S1DNS_IP" -e "$S2DNS_IP"`
if [ ! -z "$ListeDNSKO" ]
then echo "!!! $HOST Serveurs DNS /etc/resolv.conf pas conformes ou obsolétes:" $ListeDNSKO
     CRIP_NOM=1 ; KOLIST_NOM="$KOLIST_NOM+Serveurs DNS"
fi

# Nbre de DNS OK (pas de doublon ou autre)
NBDNS=0
[ -z "$S0DNS_IP" ] || let NBDNS=NBDNS+1  
[ -z "$S1DNS_IP" ] || let NBDNS=NBDNS+1
[ -z "$S2DNS_IP" ] || let NBDNS=NBDNS+1
NB=`grep -c ^nameserver /etc/resolv.conf`
if [ "$NB" -ne "$NBDNS" ]
then echo "!!! $HOST Serveurs DNS nameserver absent ou en trop: $NB nameserver au lieu de $NBDNS"
     CRIP_NOM=1 ; KOLIST_NOM="$KOLIST_NOM+Serveurs DNS"
fi

# Verifie l'orde des DNS, S0DNS_IP puis S1DNS_IP puis S2DNS_IP 
# Toujours le cache DNS en premier, S1DNS_IP=DNS=PA6 en second, puis DNS Chartres = S2DNS_IP en palliatif en troisième
grep ^nameserver  /etc/resolv.conf| grep -n .|grep -q "1:nameserver.*$S0DNS"
if [ $? -ne 0 ]
then echo "!!! Dns locale $S0DNS absente ou pas en premiére position."
     grep ^nameserver  /etc/resolv.conf| grep -n .|grep "$S0DNS"
     CRIP_NOM=1 ; KOLIST_NOM="$KOLIST_NOM+dns_ordre"
fi

grep ^nameserver  /etc/resolv.conf| grep -n .|grep -q "2:nameserver.*$S1DNSok"
if [ $? -ne 0 ]
then echo "!!! Dns primaire PA6 $S1DNSok absente ou pas en seconde position."
     grep ^nameserver  /etc/resolv.conf| grep -n .|grep "$S1DNSok"
     CRIP_NOM=1 ; KOLIST_NOM="$KOLIST_NOM+dns_ordre"
fi


grep ^nameserver  /etc/resolv.conf| grep -n .|grep -q "3:nameserver.*$S2DNSok"
if [ $? -ne 0 ]
then echo "!!! Dns secondaire Chartres $S2DNSok absente ou pas en troisieme position."
     grep ^nameserver  /etc/resolv.conf| grep -n .|grep "$S2DNSok"
     CRIP_NOM=1 ; KOLIST_NOM="$KOLIST_NOM+dns_ordre"
fi

[ "$OPverbeux" = "YES" ] && echo "#     Serveurs DNS $S1DNStype: $S0DNS_IP $S1DNS_IP $S2DNS_IP "

# Serveur DNS cache local
# -----------------------
# Si "$S0DNS_IP" présent, 
#    doit etre en premier dans /etc/resolv.conf, sinon inutile !!!!
#    /etc/named.conf doit egalement etre ok ("$S1DNS_IP" et "$S2DNS_IP" présent )
#    2021-10-26 Rajout ordre DNS ds named.conf
#    le service de nom named doit etre activé
# 
if [ ! -z "$S0DNS_IP" ]
then grep nameserver /etc/resolv.conf |head -1|grep -q $S0DNS_IP
     if [ $? -ne 0 ]
     then echo "!!! $HOST DNS nameserver=$S0DNS_IP doit etre en premier"
          CRIP_NOM=1 ; KOLIST_NOM="$KOLIST_NOM+DNS $S0DNS_IP"
     fi
     NB1=0
     NB2=0
     grep -wq "$S1DNS_IP" /etc/named.conf
     if [ $? -ne 0 ]
     then echo "!!! $HOST Pas de DNS primaire ($S1DNS_IP) dans /etc/named.conf"
          CRIP_NOM=1 ; KOLIST_NOM="$KOLIST_NOM+cache DNS"
     else NB1=`grep -wn $S1DNS_IP /etc/named.conf|cut -d ":" -f1`
     fi
     grep -wq "$S2DNS_IP" /etc/named.conf
     if [ $? -ne 0 ]
     then echo "!!! $HOST Pas de DNS secondaire  ($S2DNS_IP) dans /etc/named.conf"
          CRIP_NOM=1 ; KOLIST_NOM="$KOLIST_NOM+cache DNS"
     else NB2=`grep -wn $S2DNS_IP /etc/named.conf|cut -d ":" -f1`
     fi
     if [ "$NB1" -ne 0 -a "$NB2" -ne 0 ]
     then if [ "$NB1" -gt "$NB2" ]
          then echo "!!! $HOST Orde DNS Ko $S1DNS_IP $S2DNS_IP dans /etc/named.conf"
               CRIP_NOM=1 ; KOLIST_NOM="$KOLIST_NOM+cache DNS"
          fi
     fi

     lssrc -s named | grep -q active
     if [ $? -ne 0 ]
     then echo "!!! $HOST cache DNS configuré, mais service named 'inoperative' "
          CRIP_NOM=1 ; KOLIST_NOM="$KOLIST_NOM+dns_named"
     else [ "$OPverbeux" = "YES" ] && echo "#     Service named (cache DNS) actif"
     fi
else echo "# Warning Serveur DNS local absent "
fi



# ----------------------------------------------------------------------------------------------
# Controle LDAP/PAM
# Suite a la detection d un prob de synchro des LDAP/PAMunix, on verifie que les PAMunix ont la bonne IP
# (meme ordre de recherche LDAP/PAMunix pour les LPAR)
# 
KOLDAP=0
grep "^ldapservers:" /etc/security/ldap/ldap.cfg| grep -q "pamunix1.appli,pamunix2.appli"
if [ $? -ne 0 ]
then echo "!!! LDAP mal configure. pamunix1.appli,pamunix2.appli absent de /etc/security/ldap/ldap.cfg"
     CRIP_NOM=1 ; KOLIST_NOM="$KOLIST_NOM+LDAP"
     KOLDAP=1
else
	host pamunix1.appli|grep -q 10.56.7.15 
	if [ $? -ne 0 ]
        then echo "!!! LDAP pamunix1.appli ne pointe pas sur 10.56.7.15"
             CRIP_NOM=1 ; KOLIST_NOM="$KOLIST_NOM+LDAP"
             KOLDAP=1
        fi
	host pamunix2.appli|grep -q 10.57.7.16 
        if [ $? -ne 0 ]
        then echo "!!! LDAP pamunix2.appli ne pointe pas sur 10.56.7.16"
             CRIP_NOM=1 ; KOLIST_NOM="$KOLIST_NOM+LDAP"
             KOLDAP=1
        fi
fi
if [ "$KOLDAP" = "0" ]
then [ "$OPverbeux" = "YES" ] && echo "#     Config LDAP pamunix1.appli et pamunix2.appli OK"
fi

# On vérifie également l'accès LDAP via un lsgroup
# La connexion peut etre ok sans que les users puissent se connecter
# si le SYSTEM n'est pas LDAP+Compat dans /etc/security/user
lsgroup isa_aix | grep -q "registry=LDAP"
if [ $? -ne 0 ]
then echo "!!! LDAP Accès LDAP '(lsgroup isa_aix)' KO"
     RIP_NOM=1 ; KOLIST_NOM="$KOLIST_NOM+LDAPgrp"
else [ "$OPverbeux" = "YES" ] && echo "#     Connexion LDAP (lsgroup isa_aix) ok"
fi




# ------------------------------------------------------------------
# Gateway
# Une seule route par défaut ( controle @ip gateway plus tard avec le controle VLAN nominal)
NB=`netstat -rn|grep -c default`
if [ "$NB" = 1 ]
then GATEWAY_NOM=`netstat -rn|grep  default|awk '{ print $2}'`
else echo "!!! Absence de GATEWAY ou trop de GATEWAY"
     netstat -rn|grep - default
     CRIP_NOM=1 ; KOLIST_NOM="$KOLIST_NOM+Gateway"
     GATEWAY_NOM=absent
fi


# ------------------------------------------------------------------
# Interfaces enx
# --------------
# Il ne doit y avoir que 2 interfaces, un en nominal et un en backup
# correspondant aux IP indiques ds /etc/hots
NB=`netstat -in |  grep -v -e $IP_NOM -e $IP_BCK -e link|grep -c ^en`
if [ "$NB" -ne 0 ]
then echo "!!! $HOST Interface ne correspondant pas a  $LPAR_NOM et $LPAR_BCK"
     echo "!!! $HOST IP ds /etc/hosts fausses, ou reseau interdit PA6"
     netstat -in |  grep -v -e $IP_NOM -e $IP_BCK -e link
     CRIP_NOM=1 ; KOLIST_NOM="$KOLIST_NOM+interface interdit"
fi

# Pas d autre ent que les en configures
NB=`netstat -in |  grep -v link | grep -c ^en`
XX=`lscfg|grep -cw ent.`
if [ ! "$NB" = "$XX" ]
then  echo "!!! $HOST Nbre ENT ($XX) different du Nbre interface EN ($NB)   Interface fantome"
      CRIP_NOM=1 ; KOLIST_NOM="$KOLIST_NOM+interface fantome"
fi



# Interface NOMINAL
# -----------------
# On verifie la presence du reseau Nominal, que son adresse de reseau/VLAN soit connu PA6
# et on verifie si les parametres Netmask/Mtu ... sont conforme par rapport au réseau PA6
netstat -in|grep $IP_NOM| read EN_NOM MTU_NOM NETWORK_NOM XX
if [ -z "$NETWORK_NOM" ]
then echo "!!! $HOST Pas d interface nominale \(en?\) configure pour $IP_NOM"
     CRIP_NOM=1 ; KOLIST_NOM="$KOLIST_NOM+interface absent"
else NETMASK_NOM=`lsattr -El $EN_NOM -a netmask|awk '{print $2}'`
     MTU_NOM=`lsattr -El $EN_NOM -a mtu|awk '{print $2}'`
# Pas de MTUbypass en AIX 5.3
     [ "$OS" = "5.3.0.0" ] || MTUbypass_NOM=`lsattr -El $EN_NOM -a mtu_bypass|awk '{print $2}'`
     VLAN_NOM=`entstat -d $EN_NOM|grep "^Port VLAN"| tr -d " " |cut -d ":" -f2`
     [ "$OPverbeux" = "YES" ] && echo "#     Nominal=$EN_NOM IP=$IP_NOM Reseau=$NETWORK_NOM Vlan=$VLAN_NOM Netmask=$NETMASK_NOM MTU=$MTU_NOM Gateway=$GATEWAY_NOM"

# netwkork_lst Contient les VLAN et caractérisques habilités PA6
     netwkork_lst | grep " $NETWORK_NOM " | read VLAN_REF NETWORK_REF GATEWAY_REF NETMASK_REF NETMASKxx_REF MTU_REF SITE_REF XX
     if [ -z "$VLAN_REF" ]
     then  echo "!!! $HOST $EN_NOM Reseau $NETWORK_NOM non compatible PA6   Ip=$IP_NOM"
           CRIP_NOM=1 ; KOLIST_NOM="$KOLIST_NOM+reseau"
     else if [ ! "$NETMASK_NOM" = "$NETMASK_REF" ]
          then echo "!!! $HOST $EN_NOM Netmask $NETMASK_NOM different de celui du VLAN $VLAN_REF = $NETMASK_REF"
               CRIP_NOM=1 ; KOLIST_NOM="$KOLIST_NOM+Netmask"
          fi
          if [ ! "$VLAN_NOM" = "$VLAN_REF" ]
          then echo "!!! $HOST $EN_NOM NoVLAN $VLAN_NOM different de celui du reseau $VLAN_REF = $VLAN_REF"
               CRIP_NOM=1 ; KOLIST_NOM="$KOLIST_NOM+VLAN"
          fi
          if [ ! "$MTU_NOM" = "$MTU_REF" ]
          then echo "!!! $HOST $EN_NOM MTU=$MTU_NOM different de celui du VLAN $VLAN_REF = $MTU_REF"
               CRIP_NOM=1 ; KOLIST_NOM="$KOLIST_NOM+MTU"
          fi
          if [ "$MTU_NOM" = "9000" -a ! "$MTUbypass_NOM" = "on" -a ! "$OS" = "5.3.0.0" ]
          then echo "!!! $HOST $EN_NOM MTUbypass=$MTUbypass_NOM, devrait etre ON pour MTU=$MTU_NOM"
               CRIP_NOM=1 ; KOLIST_NOM="$KOLIST_NOM+MTUbypass"
          fi
     fi
fi

# Et Gateway // VLAN nominal
# --------------------------
if [ ! "$GATEWAY_NOM" = "$GATEWAY_REF" ]
then echo "!!! $HOST La gareway defaut "$GATEWAY_NOM" n est pas conforma pour VLAN=$VLAN_NOM GW=$GATEWAY_REF"
     CRIP_NOM=1 ; KOLIST_NOM="$KOLIST_NOM+Gateway KO"
fi





# Interface BACKUP
# ----------------
# On verifie la presence du reseau Backup, que son adresse de reseau/VLAN soit connu PA6
# et on verifie si les parametres Netmask/Mtu ... sont conforme par rapport au réseau PA6
netstat -in|grep $IP_BCK| read EN_BCK MTU_BCK NETWORK_BCK XX
if [ -z "$NETWORK_BCK" ]
then echo "!!! $HOST Pas d interface backup \(en?\) configure pour $IP_BCK"
     CRIP_BCK=1 ; KOLIST_BCK="$KOLIST_BCK+interface absent"
else NETMASK_BCK=`lsattr -El $EN_BCK -a netmask|awk '{print $2}'`
     MTU_BCK=`lsattr -El $EN_BCK -a mtu|awk '{print $2}'`
# Pas de mtu_bypass en AIX 5.3
     [ "$OS" = "5.3.0.0" ] || MTUbypass_BCK=`lsattr -El $EN_BCK -a mtu_bypass|awk '{print $2}'`
     VLAN_BCK=`entstat -d $EN_BCK|grep "^Port VLAN"| tr -d " " |cut -d ":" -f2`
     [ "$OPverbeux" = "YES" ] && echo "#     Backup=$EN_BCK IP=$IP_BCK Reseau=$NETWORK_BCK Vlan=$VLAN_BCK Netmask=$NETMASK_BCK MTU=$MTU_BCK"

# netwkork_lst Contient les VLAN et caractérisques habilités PA6
     netwkork_lst | grep " $NETWORK_BCK " | read VLAN_REF NETWORK_REF GATEWAY_REF NETMASK_REF NETMASKxx_REF MTU_REF SITE_REF XX
     if [ -z "$VLAN_REF" ]
     then  echo "!!! $HOST $EN_BCK Reseau $NETWORK_BCK non compatible PA6   Ip=$IP_BCK reseau"
           CRIP_BCK=1 ; KOLIST_BCK="$KOLIST_BCK+reseau"
     else if [ ! "$NETMASK_BCK" = "$NETMASK_REF" ]
          then echo "!!! $HOST $EN_BCK Netmask $NETMASK_BCK different de celui du VLAN $VLAN_REF = $NETMASK_REF"
               CRIP_BCK=1 ; KOLIST_BCK="$KOLIST_BCK+Netmask"
          fi
          if [ ! "$VLAN_BCK" = "$VLAN_REF" ]
          then echo "!!! $HOST $EN_BCK NoVLAN $VLAN_BCK different de celui du reseau $VLAN_REF = $VLAN_REF"
               CRIP_BCK=1 ; KOLIST_BCK="$KOLIST_BCK+VLAN"
          fi
          if [ ! "$MTU_BCK" = "$MTU_REF" ]
          then echo "!!! $HOST $EN_BCK MTU=$MTU_BCK different de celui du VLAN $VLAN_REF = $MTU_REF"
               CRIP_BCK=1 ; KOLIST_BCK="$KOLIST_BCK+MTU"
          fi
          if [ "$MTU_BCK" = "9000" -a ! "$MTUbypass_BCK" = "on" -a ! "$OS" = "5.3.0.0" ]
          then echo "!!! $HOST $EN_BCK MTUbypass=$MTUbypass_BCK, devrait etre ON pour MTU=$MTU_BCK"
               CRIP_BCK=1 ; KOLIST_BCK="$KOLIST_BCK+MTUbypass"
          fi
     fi
fi




# ------------------------------------------------------------------
# FIN des controles 

[ -z "$KOLIST_NOM"  ] || echo "!!! $HOST Reseau nominal KO: $KOLIST_NOM"
[ -z "$KOLIST_BCK"  ] || echo "!!! $HOST Reseau backup KO: $KOLIST_BCK"

if [ -z "$KOLIST_NOM" -a -z "$KOLIST_BCK"  ]
then  OK_fct $HOST Controle OK reseau nominal et backup OK
else  KO_fct 120 $HOST Reseau mal parametre.
fi


}
########################################################################################





#######################################
## MAIN
#######################################

OPverbeux=""
DEBUG=""
OPtt=""


while getopts dvh option
do
        case $option in
                v) export OPverbeux=YES 
		   ;;
		d) DEBUG="set -x"
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

$DEBUG
[ -z "$OPtt" ] && OPtt=x
[ -z "$OPverbeux" ] && OPverbeux="NO"

HOST=`hostname`
LPAR_NOM=${HOST}
LPAR_BCK=${HOST}-bck
OS=`oslevel`


#########################
# En FONCTIOn DES OPTIONs
#########################
case "$OPtt" in
	x)	ctl_lan_fct ;;	
	h)   	menu_fct ;;	
	*) KO_fct 101 Parametre de traitement inconnu.  ;;
esac



exit 0



