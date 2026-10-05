export type Locale = "ar" | "en";
export type LocalizedText = Record<Locale, string>;
export interface Category { id:string; slug:string; name:LocalizedText; description:LocalizedText; image:string }
export interface Industry { id:string; slug:string; name:LocalizedText; description:LocalizedText; image:string; ingredientIds:string[] }
export interface Product { id:string; slug:string; name:LocalizedText; shortDescription:LocalizedText; description:LocalizedText; categoryId:string; image:string; gallery:string[]; industryIds:string[]; applications:LocalizedText[]; specifications:{label:LocalizedText;value:LocalizedText}[]; packaging?:LocalizedText; availableSizes?:LocalizedText; featured:boolean; keywords:string[] }
export interface Inquiry { company:string; name:string; phone:string; email:string; product?:string; quantity?:string; message:string }
