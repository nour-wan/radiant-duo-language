import { Link,type LinkProps } from "@tanstack/react-router";
import { forwardRef,type ButtonHTMLAttributes,type ReactNode } from "react";
import { cn } from "@/lib/utils";
const styles={default:"bg-primary text-primary-foreground hover:bg-primary/90",primary:"bg-primary text-primary-foreground hover:bg-primary/90",outline:"border border-border bg-background/85 text-foreground hover:bg-accent",secondary:"border border-border bg-background/85 text-foreground hover:bg-accent",ghost:"text-foreground hover:bg-accent",link:"text-primary underline-offset-4 hover:underline",destructive:"bg-destructive text-primary-foreground",light:"bg-hero-foreground text-hero hover:bg-hero-foreground/90"};
type Variant=keyof typeof styles; type Size="default"|"sm"|"lg"|"icon";
const sizes={default:"min-h-11 px-5 py-2.5",sm:"h-9 px-3",lg:"h-12 px-7",icon:"size-11 p-0"};
export type ButtonProps=ButtonHTMLAttributes<HTMLButtonElement>&{variant?:Variant;size?:Size};
export function buttonVariants({variant="default",size="default"}:{variant?:Variant;size?:Size}={}){return cn("inline-flex items-center justify-center gap-2 rounded-md text-sm font-bold transition-colors focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-ring disabled:opacity-50",styles[variant],sizes[size])}
export const Button=forwardRef<HTMLButtonElement,ButtonProps>(({variant="default",size="default",className,...props},ref)=><button ref={ref} className={cn(buttonVariants({variant,size}),className)} {...props}/>);
Button.displayName="Button";
export function ButtonLink({variant="primary",className,children,...props}:LinkProps&{variant?:Variant;className?:string;children:ReactNode}){return <Link className={cn(buttonVariants({variant}),className)} {...props}>{children}</Link>}
