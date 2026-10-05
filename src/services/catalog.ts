import { categories, industries, products } from "@/data/catalog";
import type { Inquiry } from "@/types/catalog";
const apiUrl=import.meta.env["VITE_API_URL"];
export async function getProducts():Promise<import("@/types/catalog").Product[]>{ if(apiUrl){const r=await fetch(`${apiUrl}/products`);if(r.ok)return r.json() as Promise<import("@/types/catalog").Product[]>} return products }
export async function getProductBySlug(slug:string){return (await getProducts()).find((p:any)=>p.slug===slug)}
export async function getCategories(){return categories}
export async function getIndustries(){return industries}
export async function submitInquiry(data:Inquiry){if(apiUrl){const r=await fetch(`${apiUrl}/inquiries`,{method:"POST",headers:{"Content-Type":"application/json"},body:JSON.stringify(data)});if(!r.ok)throw new Error("Submission failed")}return {ok:true}}
