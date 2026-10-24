import cocoa from "@/assets/products/cocoa.jpg";
import apricots from "@/assets/products/apricots.jpg";
import hazelnuts from "@/assets/products/hazelnuts.jpg";
import filling from "@/assets/products/filling.jpg";
import bakery from "@/assets/products/bakery.jpg";
import icecream from "@/assets/products/icecream.jpg";
import cannedTropicalFruits from "@/assets/products/catalog/canned-tropical-fruits.jpg";
import syrups from "@/assets/products/catalog/syrups.jpg";
import fruitPurees from "@/assets/products/catalog/fruit-purees.jpg";
import type { Category, Industry, Product } from "@/types/catalog";

const t=(ar:string,en:string)=>({ar,en});
const images={chocolate:cocoa,dried:apricots,nuts:hazelnuts,bakery,icecream,flavors:icecream,oils:filling,sweeteners:bakery,stabilizers:bakery,general:hazelnuts};
type CategoryId=keyof typeof images;
const productImageModules=import.meta.glob("../assets/products/catalog/*.jpg",{eager:true,import:"default",query:"?url"}) as Record<string,string>;
const productImage=(id:string)=>{
 if(id==="canned-tropical-fruits")return cannedTropicalFruits;
 if(id==="syrups")return syrups;
 if(id==="fruit-purees")return fruitPurees;
 const image=productImageModules[`../assets/products/catalog/${id}.jpg`];
 if(!image)throw new Error(`Missing unique catalog image for ${id}`);
 return image;
};

export const categories:Category[]=[
 {id:"chocolate",slug:"chocolate-cocoa",name:t("الشوكولا والكاكاو","Chocolate & Cocoa"),description:t("كاكاو وشوكولا ومشتقاتها للتصنيع.","Cocoa, chocolate and derivatives for manufacturing."),image:cocoa},
 {id:"nuts",slug:"nuts-seeds",name:t("المكسرات والبذور","Nuts & Seeds"),description:t("مكسرات وبذور كاملة ومجهزة ومعاجين.","Whole and processed nuts, seeds and pastes."),image:hazelnuts},
 {id:"dried",slug:"dried-fruits",name:t("الفواكه المجففة","Dried Fruits"),description:t("فواكه مجففة لتطبيقات غذائية متعددة.","Dried fruits for diverse food applications."),image:apricots},
 {id:"bakery",slug:"bakery-confectionery",name:t("المخابز والحلويات","Bakery & Confectionery"),description:t("خلطات وحشوات ومحسنات وتزيين.","Mixes, fillings, improvers and decoration."),image:bakery},
 {id:"icecream",slug:"ice-cream-dairy",name:t("الآيس كريم والألبان","Ice Cream & Dairy"),description:t("قواعد ومساحيق لمصنعي الألبان والمثلجات.","Bases and powders for dairy and frozen desserts."),image:icecream},
 {id:"flavors",slug:"flavors-colors",name:t("النكهات والألوان","Flavors & Colors"),description:t("نكهات وألوان لتطوير هوية المنتج.","Flavors and colors for product development."),image:icecream},
 {id:"oils",slug:"oils-fats",name:t("الزيوت والدهون","Oils & Fats"),description:t("دهون وزيوت لتطبيقات المخابز والحلويات.","Fats and oils for bakery and confectionery."),image:filling},
 {id:"sweeteners",slug:"sugars-sweeteners",name:t("السكر والمحليات","Sugars & Sweeteners"),description:t("سكريات وشرابات لتطبيقات التصنيع الغذائي.","Sugars and syrups for food manufacturing."),image:bakery},
 {id:"stabilizers",slug:"stabilizers-emulsifiers",name:t("المثبتات والمستحلبات","Stabilizers & Emulsifiers"),description:t("حلول للقوام والثبات وتجانس المنتج.","Solutions for texture, stability and consistency."),image:bakery},
 {id:"general",slug:"general-food-ingredients",name:t("مكونات غذائية متنوعة","General Food Ingredients"),description:t("أحماض وأملاح ومساحيق للاستخدام الصناعي.","Acids, salts and powders for industrial use."),image:hazelnuts},
];

const specs=(formAr:string,formEn:string)=>[
 {label:t("الشكل","Form"),value:t(formAr,formEn)},
 {label:t("درجة الاستخدام","Application grade"),value:t("مخصص للتصنيع الغذائي","Food manufacturing")},
 {label:t("التخزين","Storage"),value:t("وفق نشرة المنتج الفنية","Per product technical sheet")},
];
const apps:Record<string,[string,string][]>={
 choc:[["الشوكولا والحلويات","Chocolate & confectionery"],["البسكويت والويفر","Biscuits & wafers"]],
 bakery:[["المخابز والمعجنات","Bakeries & pastries"],["الكيك والحلويات","Cakes & desserts"]],
 ice:[["الآيس كريم","Ice cream"],["الألبان والحلويات المجمدة","Dairy & frozen desserts"]],
 food:[["تصنيع الأغذية","Food manufacturing"],["المشروبات والخلطات","Beverages & mixes"]],
};
type Seed={id:string;ar:string;en:string;cat:CategoryId;inds:string[];formAr?:string;formEn?:string;featured?:boolean;keywords?:string[];shortAr?:string;shortEn?:string;descriptionAr?:string;descriptionEn?:string;applicationPairs?:[string,string][]};
const seeds:Seed[]=[
 {id:"natural-cocoa",ar:"مسحوق كاكاو طبيعي",en:"Natural Cocoa Powder",cat:"chocolate",inds:["choc","bakeries","biscuits","cakes","beverages"],featured:true},
 {id:"alkalized-cocoa",ar:"مسحوق كاكاو معالج",en:"Alkalized Cocoa Powder",cat:"chocolate",inds:["choc","bakeries","biscuits","ice","beverages"]},
 {id:"cocoa-butter",ar:"زبدة الكاكاو",en:"Cocoa Butter",cat:"chocolate",inds:["choc","cakes","ice"],formAr:"كتل أو رقائق",formEn:"Blocks or chips"},
 {id:"cocoa-mass",ar:"كتلة الكاكاو",en:"Cocoa Mass",cat:"chocolate",inds:["choc","cakes"],formAr:"كتل",formEn:"Blocks"},
 {id:"dark-couverture",ar:"شوكولا خام داكنة",en:"Dark Couverture Chocolate",cat:"chocolate",inds:["choc","bakeries","biscuits","cakes","ice"],formAr:"أقراص أو قطع",formEn:"Callets or blocks",featured:true},
 {id:"milk-couverture",ar:"شوكولا خام بالحليب",en:"Milk Couverture Chocolate",cat:"chocolate",inds:["choc","bakeries","biscuits","cakes","ice"],formAr:"أقراص أو قطع",formEn:"Callets or blocks"},
 {id:"white-couverture",ar:"شوكولا خام بيضاء",en:"White Couverture Chocolate",cat:"chocolate",inds:["choc","bakeries","cakes","ice"],formAr:"أقراص أو قطع",formEn:"Callets or blocks"},
 {id:"chocolate-chips",ar:"حبيبات شوكولا",en:"Chocolate Chips",cat:"chocolate",inds:["bakeries","biscuits","cakes"],formAr:"حبيبات",formEn:"Chips"},
 {id:"hazelnuts",ar:"بندق",en:"Hazelnuts",cat:"nuts",inds:["choc","bakeries","biscuits","cakes","ice"],featured:true},
 {id:"pistachios",ar:"فستق حلبي",en:"Pistachios",cat:"nuts",inds:["choc","bakeries","cakes","ice"]},
 {id:"almonds",ar:"لوز",en:"Almonds",cat:"nuts",inds:["choc","bakeries","biscuits","cakes"]},
 {id:"cashews",ar:"كاجو",en:"Cashews",cat:"nuts",inds:["choc","bakeries","food"]},
 {id:"walnuts",ar:"جوز",en:"Walnuts",cat:"nuts",inds:["bakeries","cakes","food"]},
 {id:"peanuts",ar:"فول سوداني",en:"Peanuts",cat:"nuts",inds:["choc","bakeries","biscuits","food"]},
 {id:"nut-paste",ar:"معجون مكسرات",en:"Nut Paste",cat:"nuts",inds:["choc","bakeries","cakes","ice"],formAr:"معجون",formEn:"Paste"},
 {id:"sesame",ar:"سمسم",en:"Sesame Seeds",cat:"nuts",inds:["bakeries","food"],formAr:"بذور",formEn:"Seeds"},
 {id:"dried-apricots",ar:"مشمش مجفف",en:"Dried Apricots",cat:"dried",inds:["choc","bakeries","cakes","food"],featured:true},
 {id:"raisins",ar:"زبيب",en:"Raisins",cat:"dried",inds:["bakeries","biscuits","cakes","food"]},
 {id:"dried-dates",ar:"تمر مجفف",en:"Dried Dates",cat:"dried",inds:["bakeries","cakes","food"]},
 {id:"dried-figs",ar:"تين مجفف",en:"Dried Figs",cat:"dried",inds:["bakeries","cakes","food"]},
 {id:"dried-cranberries",ar:"توت بري مجفف",en:"Dried Cranberries",cat:"dried",inds:["bakeries","cakes","food"]},
 {id:"coconut-flakes",ar:"رقائق جوز الهند",en:"Coconut Flakes",cat:"dried",inds:["choc","bakeries","cakes","ice"],formAr:"رقائق",formEn:"Flakes"},
 {id:"bakery-base-mix",ar:"خليط أساس للمخابز",en:"Bakery Base Mix",cat:"bakery",inds:["bakeries","biscuits","cakes"],formAr:"مسحوق",formEn:"Powder"},
 {id:"bread-improver",ar:"محسن خبز",en:"Bread Improver",cat:"bakery",inds:["bakeries"],formAr:"مسحوق",formEn:"Powder"},
 {id:"baking-powder",ar:"مسحوق الخَبز",en:"Baking Powder",cat:"bakery",inds:["bakeries","biscuits","cakes"],formAr:"مسحوق",formEn:"Powder"},
 {id:"dry-yeast",ar:"خميرة جافة",en:"Dry Yeast",cat:"bakery",inds:["bakeries"],formAr:"حبيبات",formEn:"Granules"},
 {id:"corn-starch",ar:"نشا الذرة",en:"Corn Starch",cat:"bakery",inds:["bakeries","biscuits","cakes","food"],formAr:"مسحوق",formEn:"Powder"},
 {id:"chocolate-filling",ar:"حشوة شوكولا",en:"Chocolate Filling",cat:"bakery",inds:["choc","bakeries","biscuits","cakes","ice"],formAr:"حشوة كريمية",formEn:"Cream filling",featured:true},
 {id:"fruit-filling",ar:"حشوة فواكه",en:"Fruit Filling",cat:"bakery",inds:["bakeries","cakes","ice"],formAr:"حشوة",formEn:"Filling"},
 {id:"neutral-glaze",ar:"جيل تلميع محايد",en:"Neutral Glaze",cat:"bakery",inds:["bakeries","cakes"],formAr:"جيل",formEn:"Gel"},
 {id:"sprinkles",ar:"حبيبات تزيين",en:"Decorative Sprinkles",cat:"bakery",inds:["choc","bakeries","cakes","ice"],formAr:"حبيبات",formEn:"Sprinkles"},
 {id:"icecream-base",ar:"قاعدة آيس كريم",en:"Ice Cream Base",cat:"icecream",inds:["ice"],formAr:"مسحوق",formEn:"Powder",featured:true},
 {id:"milk-powder",ar:"حليب مجفف",en:"Milk Powder",cat:"icecream",inds:["choc","bakeries","biscuits","ice","beverages"],formAr:"مسحوق",formEn:"Powder"},
 {id:"whey-powder",ar:"مسحوق مصل الحليب",en:"Whey Powder",cat:"icecream",inds:["bakeries","biscuits","ice","beverages"],formAr:"مسحوق",formEn:"Powder"},
 {id:"cream-powder",ar:"مسحوق القشطة",en:"Cream Powder",cat:"icecream",inds:["bakeries","cakes","ice"],formAr:"مسحوق",formEn:"Powder"},
 {id:"soft-serve-mix",ar:"خليط آيس كريم سوفت",en:"Soft Serve Mix",cat:"icecream",inds:["ice"],formAr:"خليط مسحوق",formEn:"Powder mix"},
 {id:"vanilla-flavor",ar:"نكهة فانيلا",en:"Vanilla Flavor",cat:"flavors",inds:["choc","bakeries","biscuits","cakes","ice","beverages"],formAr:"سائل أو مسحوق",formEn:"Liquid or powder",featured:true},
 {id:"strawberry-flavor",ar:"نكهة فراولة",en:"Strawberry Flavor",cat:"flavors",inds:["cakes","ice","beverages"],formAr:"سائل أو مسحوق",formEn:"Liquid or powder"},
 {id:"caramel-flavor",ar:"نكهة كراميل",en:"Caramel Flavor",cat:"flavors",inds:["choc","bakeries","cakes","ice","beverages"]},
 {id:"food-colors",ar:"ألوان غذائية",en:"Food Colors",cat:"flavors",inds:["choc","bakeries","cakes","ice","beverages"],formAr:"مسحوق أو سائل",formEn:"Powder or liquid"},
 {id:"palm-oil",ar:"زيت نخيل مكرر",en:"Refined Palm Oil",cat:"oils",inds:["choc","bakeries","biscuits","food"],formAr:"سائل أو نصف صلب",formEn:"Liquid or semi-solid"},
 {id:"bakery-shortening",ar:"شورتنينغ للمخابز",en:"Bakery Shortening",cat:"oils",inds:["bakeries","biscuits","cakes"],formAr:"دهن نصف صلب",formEn:"Semi-solid fat"},
 {id:"industrial-margarine",ar:"مارغرين صناعي",en:"Industrial Margarine",cat:"oils",inds:["bakeries","biscuits","cakes"]},
 {id:"cocoa-butter-substitute",ar:"بديل زبدة الكاكاو",en:"Cocoa Butter Substitute",cat:"oils",inds:["choc","biscuits"]},
 {id:"coconut-oil",ar:"زيت جوز الهند",en:"Coconut Oil",cat:"oils",inds:["choc","bakeries","ice","food"]},
 {id:"white-sugar",ar:"سكر أبيض",en:"White Sugar",cat:"sweeteners",inds:["choc","bakeries","biscuits","cakes","ice","beverages","food"]},
 {id:"glucose-syrup",ar:"شراب الغلوكوز",en:"Glucose Syrup",cat:"sweeteners",inds:["choc","bakeries","cakes","ice","beverages"],formAr:"شراب",formEn:"Syrup",featured:true},
 {id:"dextrose",ar:"ديكستروز",en:"Dextrose",cat:"sweeteners",inds:["choc","bakeries","ice","beverages"],formAr:"مسحوق",formEn:"Powder"},
 {id:"invert-sugar",ar:"سكر محوّل",en:"Invert Sugar Syrup",cat:"sweeteners",inds:["choc","bakeries","cakes","ice"],formAr:"شراب",formEn:"Syrup"},
 {id:"sorbitol",ar:"سوربيتول",en:"Sorbitol",cat:"sweeteners",inds:["choc","bakeries","food"],formAr:"مسحوق أو شراب",formEn:"Powder or syrup"},
 {id:"lecithin",ar:"ليسيثين",en:"Lecithin",cat:"stabilizers",inds:["choc","bakeries","biscuits","ice","food"],formAr:"سائل أو مسحوق",formEn:"Liquid or powder",featured:true},
 {id:"mono-diglycerides",ar:"أحادي وثنائي الغليسيريد",en:"Mono & Diglycerides",cat:"stabilizers",inds:["bakeries","biscuits","ice","food"]},
 {id:"xanthan-gum",ar:"صمغ الزانثان",en:"Xanthan Gum",cat:"stabilizers",inds:["ice","beverages","food"],formAr:"مسحوق",formEn:"Powder"},
 {id:"guar-gum",ar:"صمغ الغوار",en:"Guar Gum",cat:"stabilizers",inds:["bakeries","ice","beverages","food"],formAr:"مسحوق",formEn:"Powder"},
 {id:"pectin",ar:"بكتين",en:"Pectin",cat:"stabilizers",inds:["cakes","ice","beverages","food"],formAr:"مسحوق",formEn:"Powder"},
 {id:"carrageenan",ar:"كاراجينان",en:"Carrageenan",cat:"stabilizers",inds:["ice","beverages","food"],formAr:"مسحوق",formEn:"Powder"},
 {id:"cmc",ar:"كربوكسي ميثيل سيليلوز",en:"CMC",cat:"stabilizers",inds:["ice","beverages","food"],formAr:"مسحوق",formEn:"Powder"},
 {id:"maltodextrin",ar:"مالتوديكسترين",en:"Maltodextrin",cat:"general",inds:["bakeries","ice","beverages","food"],formAr:"مسحوق",formEn:"Powder"},
 {id:"citric-acid",ar:"حمض الستريك",en:"Citric Acid",cat:"general",inds:["cakes","ice","beverages","food"],formAr:"بلورات أو مسحوق",formEn:"Crystals or powder"},
 {id:"sodium-bicarbonate",ar:"بيكربونات الصوديوم",en:"Sodium Bicarbonate",cat:"general",inds:["bakeries","biscuits","food"],formAr:"مسحوق",formEn:"Powder"},
 {id:"food-grade-salt",ar:"ملح غذائي",en:"Food Grade Salt",cat:"general",inds:["bakeries","biscuits","food"],formAr:"بلورات",formEn:"Crystals"},
 {id:"potassium-sorbate",ar:"سوربات البوتاسيوم",en:"Potassium Sorbate",cat:"general",inds:["bakeries","cakes","beverages","food"],formAr:"مسحوق أو حبيبات",formEn:"Powder or granules"},
 {id:"sodium-benzoate",ar:"بنزوات الصوديوم",en:"Sodium Benzoate",cat:"general",inds:["beverages","food"],formAr:"مسحوق أو حبيبات",formEn:"Powder or granules"},
  {id:"canned-tropical-fruits",ar:"فواكه معلبة استوائية",en:"Canned Tropical Fruits",cat:"general",inds:["bakeries","cakes","ice","food"],formAr:"قطع فواكه معلبة",formEn:"Canned fruit pieces",keywords:["أناناس","مانجو","بابايا","معلبات","pineapple","mango","papaya","canned"],shortAr:"فواكه استوائية معلبة لتطبيقات الحلويات والمخبوزات والآيس كريم.",shortEn:"Canned tropical fruits for desserts, bakery and ice cream applications.",descriptionAr:"فواكه استوائية معلبة لاستخدامها في الحلويات وتزيين الكيك والمخبوزات والآيس كريم. تُناقش تشكيلة الفواكه وحجم القطع ووسط الحفظ والتعبئة بحسب احتياجات التطبيق.",descriptionEn:"Canned tropical fruits for desserts, cake decoration, baked goods and ice cream. Fruit selection, piece size, preserving medium and packaging are discussed according to application needs.",applicationPairs:[["الحلويات وتزيين الكيك","Desserts & cake decoration"],["المخبوزات","Baked goods"],["الآيس كريم","Ice cream"]]},
  {id:"syrups",ar:"سيروبات",en:"Syrups",cat:"sweeteners",inds:["beverages","cakes","ice","bakeries","food"],formAr:"سائل لزج",formEn:"Viscous liquid",keywords:["سيروب","شراب","مشروبات","syrup","beverage"],shortAr:"سيروبات لتطبيقات المشروبات والحلويات والآيس كريم.",shortEn:"Syrups for beverages, desserts and ice cream applications.",descriptionAr:"سيروبات للاستخدام في المشروبات والحلويات والآيس كريم، مع مناقشة النكهة والتركيز والقوام والتعبئة المناسبة لكل تطبيق عند الاستفسار.",descriptionEn:"Syrups for beverages, desserts and ice cream. Flavor, concentration, consistency and suitable packaging are discussed for each application on inquiry.",applicationPairs:[["المشروبات والخلطات","Beverages & mixes"],["الحلويات","Desserts"],["الآيس كريم","Ice cream"]]},
  {id:"fruit-purees",ar:"فواكه مهروسة للحشوات",en:"Fruit Purees for Fillings",cat:"bakery",inds:["bakeries","cakes","biscuits","ice","food"],formAr:"هريس فواكه",formEn:"Fruit puree",keywords:["هريس","بيوريه","حشوات","puree","purée","fillings"],shortAr:"هريس فواكه لتحضير حشوات المخبوزات والكيك والحلويات.",shortEn:"Fruit purees for preparing bakery, cake and dessert fillings.",descriptionAr:"فواكه مهروسة تستخدم كأساس لتحضير حشوات الكيك والمعجنات والحلويات. يُناقش نوع الفاكهة والقوام والمعالجة المطلوبة ومدى ملاءمتها للخَبز بحسب المنتج والتطبيق.",descriptionEn:"Fruit purees used as a base for cake, pastry and dessert fillings. Fruit type, texture, required processing and suitability for baking are discussed according to the product and application.",applicationPairs:[["حشوات المعجنات","Pastry fillings"],["حشوات الكيك والحلويات","Cake & dessert fillings"],["حشوات البسكويت","Biscuit fillings"]]},
];

export const products:Product[]=seeds.map((s,index)=>{
 const category=categories.find(c=>c.id===s.cat);
  const applicationPairs=s.applicationPairs?.map(([ar,en])=>t(ar,en))??[...new Set(s.inds.flatMap(i=>apps[i]||apps["food"]||[]).map(x=>x.join("|")))].slice(0,3).map(value=>{const parts=value.split("|");return t(parts[0]??"تصنيع غذائي",parts[1]??"Food manufacturing")});
 const image=productImage(s.id);
  return {id:s.id,slug:s.id,name:t(s.ar,s.en),shortDescription:t(s.shortAr??`${s.ar} لتطبيقات صناعية غذائية متعددة.`,s.shortEn??`${s.en} for multiple food manufacturing applications.`),description:t(s.descriptionAr??`مكوّن ضمن فئة ${category?.name.ar||"المكونات الغذائية"}، متاح للمناقشة بحسب التطبيق والمواصفات والتعبئة المطلوبة.`,s.descriptionEn??`An ingredient in ${category?.name.en||"food ingredients"}, available for discussion based on application, specification and packaging needs.`),categoryId:s.cat,image,gallery:[image],industryIds:s.inds,applications:applicationPairs,specifications:specs(s.formAr||"حسب مواصفة المنتج",s.formEn||"Per product specification"),packaging:t("خيارات تعبئة صناعية — التفاصيل عند الطلب","Industrial packaging options — details on request"),featured:s.featured??index%13===0,keywords:[s.ar,s.en,s.cat,...(s.keywords||[])]};
});

if(new Set(products.map(product=>product.image)).size!==products.length){
 throw new Error("Every catalog product must have a unique image");
}

const industrySeeds=[
 ["choc","chocolate-confectionery","معامل الشوكولا والحلويات","Chocolate & Confectionery","كاكاو وشوكولا ومكسرات وحشوات لتطبيقات متنوعة.","Cocoa, chocolate, nuts and fillings for varied applications.",cocoa],
 ["bakeries","bakeries-pastries","المخابز والمعجنات","Bakeries & Pastries","خلطات ومحسنات وحشوات ودهون للمخبوزات.","Mixes, improvers, fillings and fats for baked goods.",bakery],
 ["biscuits","biscuits-wafers","معامل البسكويت والويفر","Biscuits & Wafers","مكونات للعجين والحشوات والتغطية والقوام.","Ingredients for dough, fillings, coating and texture.",filling],
 ["ice","ice-cream","معامل الآيس كريم والألبان","Ice Cream & Dairy","قواعد ومنكهات ومساحيق ومثبتات للمنتجات المجمدة.","Bases, flavors, powders and stabilizers for frozen products.",icecream],
 ["cakes","cakes-desserts","مصانع الكيك والحلويات","Cakes & Desserts","مكونات للكيك والحشوات والتزيين والحلويات.","Ingredients for cakes, fillings, decoration and desserts.",apricots],
 ["beverages","beverages","مصانع المشروبات والعصائر","Beverages & Juices","محليات ونكهات وألوان ومثبتات لتطبيقات المشروبات.","Sweeteners, flavors, colors and stabilizers for beverages.",icecream],
 ["food","food-manufacturing","مصانع الأغذية العامة","General Food Manufacturing","مكونات وظيفية ومواد أولية لخطوط إنتاج متعددة.","Functional ingredients and raw materials for varied production lines.",hazelnuts],
] as const;
export const industries:Industry[]=industrySeeds.map(([id,slug,ar,en,arDesc,enDesc,image])=>({id,slug,name:t(ar,en),description:t(arDesc,enDesc),image,ingredientIds:products.filter(p=>p.industryIds.includes(id)).map(p=>p.id)}));
