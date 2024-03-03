/*
la sofia a donné des droits :
GRANT SELECT ON sid_auteur TO miage_ed;
GRANT SELECT ON sid_bibliotheque TO miage_ed;
GRANT SELECT ON sid_contribution_forfaitaire TO miage_ed ;
GRANT SELECT ON sid_droits_achat TO miage_ed ;
GRANT SELECT ON sid_droits_pret TO miage_ed ;
GRANT SELECT ON sid_oeuvre TO miage_ed ;
GRANT SELECT ON sid_ssgenre TO miage_ed ;
GRANT SELECT ON sid_temps TO miage_ed;

ensuite l'utilisateur crée des synonymes :
create synonym ctp_auteur for sofia.sid_auteur;
create synonym ctp_bibliotheque for sofia.sid_bibliotheque;
create synonym ctp_contribution_forfaitaire for sofia.sid_contribution_forfaitaire;
create synonym ctp_droits_achat for sofia.sid_droits_achat;
create synonym ctp_droits_pret for sofia.sid_droits_pret;
create synonym ctp_oeuvre for sofia.sid_oeuvre;
create synonym ctp_ssgenre for sofia.sid_ssgenre;
create synonym ctp_temps for sofia.sid_temps;'
*/

-- De manière générale, j'ai parfois ajouté un order by pour faciliter la vérification
-- mais aucun n'était demandé.

-- Requete 1 : somme globale versée par les bibliothèques aux auteurs chaque mois_année avec le système actuel (calculé selon les achats)
-- Remarque : la table CTP_DROITS_ACHAT suffit, pas besoin de jointure
SELECT  idt,
sum(droits_par_auteur) AS montant_total
FROM CTP_DROITS_ACHAT sda
GROUP BY  idt
ORDER BY  idt;

-- Requete 2 : contribution moyenne annuelle de l'état depuis 2020
SELECT avg(sum(contribution_totale)) AS contribution_moyenne
FROM CTP_CONTRIBUTION_FORFAITAIRE scf
WHERE annee >= 2020
GROUP BY annee;

/*
---- pour faciliter l'écriture de la requête précédente, on peut commencer par calculer la contribution totale de l'état par an depuis 2020
SELECT annee, sum(contribution_totale) AS contribution_totale_annuelle
FROM CTP_CONTRIBUTION_FORFAITAIRE scf
WHERE annee >= 2020
GROUP BY annee;
*/

-- Requete 3 : somme avec le système actuel (achats) par theme, année, theme seul, toutes données confondues
select theme, annee, sum(droits_par_auteur) AS montant
from CTP_droits_achat
join CTP_oeuvre using (ido)
join CTP_temps using(idt)
group by rollup (theme, annee);

-- Requete 4 : somme globale versée aux auteurs avec le nouveau système (calculé selon les prets), par année et thème d'une part, par année et age_cible d'autre part.
SELECT  annee, theme, age_cible,
sum(coef_droits_par_auteur) AS montant_total
FROM CTP_DROITS_pret sdp
join CTP_oeuvre using (ido)
join CTP_temps using(idt)
GROUP BY  grouping sets ((annee,theme), (annee, age_cible))
ORDER BY theme, age_cible, annee;

-- Requete 5 : le nombre de prets par annee, genre et toutes les combinaisons de ces 2 axes d'analyse.
SELECT st.annee, ss.LIB_GENRE, sum(nb_exemplaires_pretes) AS nb_total_prets
FROM CTP_DROITS_PRET sdp
JOIN CTP_SSGENRE ss using(idssg)
JOIN CTP_TEMPS st using(idt)
GROUP BY CUBE (ss.LIB_GENRE, st.ANNEE)

-- ERRATUM : la requête précédente est celle dont vous avez les résultats dans le sujet
-- mais comme chaque prêt est compté pour chaque co-auteur, il faut diviser par le nb de co-auteurs :
SELECT st.annee, ss.LIB_GENRE, sum(nb_exemplaires_pretes/nb_coauteurs) AS nb_total_prets
FROM CTP_DROITS_PRET sdp
JOIN CTP_SSGENRE ss using(idssg)
JOIN CTP_TEMPS st using(idt)
GROUP BY CUBE (ss.LIB_GENRE, st.ANNEE)

-- Requete 6 : les auteurs qui auraient gagné le plus en 2022 avec le nouveau système.
-- Ici on veut le top 3 des rémunérations.
WITH classement_auteurs_2022 as(
SELECT ida, nom, prenom, sum(coef_droits_par_auteur) AS montant_total_v2,
dense_RANK() OVER (ORDER BY sum(coef_droits_par_auteur) desc) rang
FROM CTP_DROITS_pret sdp
JOIN CTP_AUTEUR sa USING(ida)
JOIN CTP_TEMPS st using(idt)
WHERE st.annee = 2022
GROUP BY ida, nom, prenom)
SELECT * FROM classement_auteurs_2022
WHERE rang <=3 ;

-- Requete 7 : chaque année, l'auteur qui a gagné le plus avec le système actuel.
-- Ici on veut seulement le premier (éventuellement avec des ex aequo)
WITH classement_by_annee AS
(SELECT annee, ida, nom, prenom,
RANK() OVER (PARTITION BY st.annee ORDER BY sum(droits_par_auteur) desc) rang,
sum(droits_par_auteur) AS montant
FROM CTP_DROITS_achat sdp
JOIN CTP_AUTEUR sa USING(ida)
JOIN CTP_TEMPS st using(idt)
GROUP BY st.annee, ida, nom, prenom )
SELECT annee, ida, nom, prenom, montant FROM classement_by_annee WHERE rang=1
ORDER BY annee ;

-- Requete 8 : les montants récoltés pour chaque age cible, par theme des oeuvres
-- indication : créer des nouveaux attributs de valeur 0 ou droits_par_auteur avec un case :
-- CASE when condition then droits_par_auteur else 0 end
select theme, sum(case when age_cible='enfant' then droits_par_auteur else 0 end) AS total_enfant,
sum(case when age_cible='adolescent' then droits_par_auteur else 0 end) AS total_adolescent,
sum(case when age_cible='adulte' then droits_par_auteur else 0 end) AS total_adulte,
sum(droits_par_auteur) AS total
from CTP_droits_achat
join CTP_oeuvre using (ido)
group by theme;

-- Requete 9 : sommes récoltées par mois_annee en comparant les 2 systèmes, en supposant qu'on verse 1 euro à chaque emprunt
-- attention, il n'y a pas d'achat ni d'emprunt tous les mois
with req1 as(
SELECT  idt,
sum(droits_par_auteur) AS montant_total_v1
FROM CTP_DROITS_ACHAT sda
GROUP BY  idt
),
req2 as(
SELECT  idt,
sum(coef_droits_par_auteur) AS montant_total_v2
FROM CTP_DROITS_pret sdp
GROUP BY  idt
)
select idt, nvl(montant_total_v1,0) AS montant_v1, nvl(montant_total_v2,0) AS montant_v2
from CTP_temps
LEFT join req1 using(idt)
LEFT join req2 using(idt)
ORDER BY idt;




-- entraianemtn 
