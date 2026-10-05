import { createContext,useContext,useEffect,useState,type ReactNode } from "react";
import type { Locale } from "@/types/catalog";
type Theme="light"|"dark";
const SiteContext=createContext<{locale:Locale;theme:Theme;setLocale:(l:Locale)=>void;toggleTheme:()=>void}|null>(null);
export function SiteProvider({children}:{children:ReactNode}){
 const [locale,setLocaleState]=useState<Locale>("ar"); const [theme,setTheme]=useState<Theme>("light");
 useEffect(()=>{const l=localStorage.getItem("janna-locale");const th=localStorage.getItem("janna-theme");if(l==="ar"||l==="en")setLocaleState(l);if(th==="dark"||th==="light")setTheme(th)},[]);
 useEffect(()=>{document.documentElement.lang=locale;document.documentElement.dir=locale==="ar"?"rtl":"ltr";document.documentElement.classList.toggle("dark",theme==="dark");localStorage.setItem("janna-locale",locale);localStorage.setItem("janna-theme",theme)},[locale,theme]);
 return <SiteContext.Provider value={{locale,theme,setLocale:(l)=>setLocaleState(l),toggleTheme:()=>setTheme(t=>t==="light"?"dark":"light")}}>{children}</SiteContext.Provider>
}
export function useSite(){const c=useContext(SiteContext);if(!c)throw new Error("SiteProvider missing");return c}
export const tr=(locale:Locale,ar:string,en:string)=>locale==="ar"?ar:en;
