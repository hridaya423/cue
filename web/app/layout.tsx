import type { Metadata, Viewport } from "next";
import "./globals.css";

export const metadata: Metadata = {
  metadataBase: new URL("https://cue.hridya.tech"),
  title: "Cue: smart paste for Mac | A better instinct for paste",
  description:
    "Cue is a clipboard for Mac that reads the field you're in and pastes the part of what you copied that fits. On-device models, plain paste when unsure.",
  alternates: { canonical: "/" },
  icons: { icon: "/favicon.svg", apple: "/apple-touch-icon.png" },
  openGraph: {
    type: "website",
    url: "/",
    title: "Cue | A better instinct for paste",
    description: "A clipboard for Mac that pastes the part that fits the field.",
    images: "/og.png",
  },
  twitter: { card: "summary_large_image" },
};

export const viewport: Viewport = { colorScheme: "only light", themeColor: "#2040e6" };

const boot = `document.documentElement.classList.add('js');(function(){var seen=false;try{seen=sessionStorage.getItem('cue-intro')==='1'}catch(e){}if(/^\\/(index\\.html)?$/.test(location.pathname)&&!matchMedia('(prefers-reduced-motion: reduce)').matches&&(/[?&]intro\\b/.test(location.search)||!seen))document.documentElement.classList.add('is-intro')})()`;

export default function RootLayout({ children }: Readonly<{ children: React.ReactNode }>) {
  return (
    <html lang="en" suppressHydrationWarning>
      <head>
        <script dangerouslySetInnerHTML={{ __html: boot }} />
        <link rel="preload" href="/fonts/geist-700.woff2" as="font" type="font/woff2" crossOrigin="" />
        <link rel="preload" href="/fonts/geist-500.woff2" as="font" type="font/woff2" crossOrigin="" />
      </head>
      <body>
        <a className="skip-link" href="#main">Skip to content</a>
        {children}
      </body>
    </html>
  );
}
