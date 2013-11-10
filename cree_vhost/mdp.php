<?php 
// usage de ce fichier: appel en ligne de commande 
//      php -f ce_fichier.php -- mot_de_pass_a_crypter
// retourne la valeur cryptée de l'argument mot_de_pass_a_crypter
echo crypt($argv[1]);
?>