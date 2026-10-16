/// Canadian French notes for [substitutionRules], keyed
/// `fromProductId:toProductId`. Safety wording (temperatures, allergen
/// warnings) must stay as faithful as the English.
const substitutionNotesFr = <String, String>{
  'butter:olive_oil': 'Utilisez-en un peu moins ; idéal pour faire sauter, pas pour la pâtisserie.',
  'milk:coconut_milk': 'Plus riche et sans produits laitiers ; ajoute une douce note de coco.',
  'cream:coconut_milk': 'Sans produits laitiers et onctueux dans les sauces et les soupes.',
  'cream:greek_yogurt': 'Incorporez hors du feu pour éviter qu\'il tranche.',
  'greek_yogurt:cream': 'Utilisez-en moitié moins pour plus d\'onctuosité.',
  'parmesan:cheddar': 'Un cheddar fort donne une profondeur salée semblable.',
  'parmesan:feta': 'Plus salée et plus acidulée ; assaisonnez avec soin.',
  'lemon:lime': 'Vive et un peu plus florale.',
  'lime:lemon': 'Vif et un brin plus doux.',
  'spinach:kale': 'Retirez les tiges et prolongez la cuisson d\'une minute ou deux.',
  'kale:spinach': 'Les épinards tombent en quelques secondes ; ajoutez-les à la fin.',
  'rice:quinoa': 'Plus de protéines ; faites cuire 15 minutes dans deux fois son volume d\'eau.',
  'quinoa:rice': 'Le basmati convient bien ; ajustez le temps de cuisson.',
  'chickpeas:black_beans': 'Texture plus tendre, goût plus terreux.',
  'black_beans:chickpeas': 'Saveur plus grillée et texture plus ferme.',
  'salmon:cod': 'Plus maigre ; raccourcissez la cuisson de quelques minutes.',
  'cod:salmon': 'Plus riche ; cuisez jusqu\'à 70 °C (158 °F).',
  'chicken_breast:tofu': 'Pressez-le d\'abord pour obtenir une croûte dorée.',
  'tofu:chicken_breast': 'Cuisez à cœur jusqu\'à 74 °C (165 °F).',
  'ground_beef:lentils': 'Utilisez des lentilles rouges sèches et une tasse de liquide de plus.',
  'shrimp:chicken_breast': 'Tranchez finement ; cuisez à cœur jusqu\'à 74 °C (165 °F).',
  'shrimp:tofu': 'Une option végétale ; saisissez jusqu\'à ce qu\'il soit doré.',
  'basil:parsley': 'Plus frais, moins sucré.',
  'cilantro:parsley': 'Une bonne option si la coriandre goûte le savon pour vous.',
  'parsley:basil': 'Plus sucré et plus aromatique.',
  'honey:maple_syrup': 'Convient aux véganes ; un peu plus liquide.',
  'maple_syrup:honey': 'Un peu plus sucré et plus épais.',
  'sugar:maple_syrup': 'Réduisez légèrement les autres liquides.',
  'tortilla:bread': 'Servez plutôt en sandwichs ouverts.',
  'almonds:walnuts': 'Plus tendres, un peu amères.',
  'walnuts:almonds': 'Plus croquantes et plus douces.',
  'peanut_butter:tahini': 'Sans arachides ; saveur plus grillée, moins sucré. Contient du sésame.',
  'tahini:peanut_butter': 'Plus sucré et plus riche. Contient des arachides.',
  'sweet_potato:potato': 'Moins sucrée ; temps de rôtissage semblable.',
  'potato:sweet_potato': 'Plus sucrée ; rôtit un peu plus vite.',
  'bell_pepper:zucchini': 'Plus doux ; faites cuire jusqu\'à ce qu\'elle soit juste tendre.',
  'pasta:quinoa': 'Un bol de céréales sans gluten au lieu des pâtes.',
};

/// The note to show for the swap [fromId] → [toId]: French when [french] and
/// a translation exists, otherwise the [english] rule note.
String substitutionNoteFor(String fromId, String toId, String english, bool french) =>
    french ? (substitutionNotesFr['$fromId:$toId'] ?? english) : english;
