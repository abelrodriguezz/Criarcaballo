/**
 * Texto legal mostrado en /terminos y enlazado desde el checkbox de
 * Registro/Login. Se guarda tal cual lo entregó el dueño del proyecto
 * (en inglés, sin traducir — un documento legal no se traduce
 * automáticamente sin revisión), con un solo cambio: el nombre de la
 * plataforma ("Forex Fusion" en el original) se reemplazó por "Trade4U"
 * para que coincida con el producto real.
 */
export interface SeccionLegal {
  numero: string;
  titulo: string;
  contenido: string[];
}

export const SECCIONES_TERMINOS: SeccionLegal[] = [
  {
    numero: "1",
    titulo: "Introduction",
    contenido: [
      'Trade4U ("we," "us," or "our") is committed to protecting your privacy. This Privacy Policy explains how we collect, use, disclose, and safeguard your personal information when you use our stock trading platform (the "Platform"). By accessing the Platform, you agree to the terms of this Policy.',
    ],
  },
  {
    numero: "2",
    titulo: "Information We Collect",
    contenido: [],
  },
  {
    numero: "2.1",
    titulo: "Information You Provide",
    contenido: [
      "Account Data: Name, email, phone number, Social Security Number (SSN), date of birth, government-issued ID.",
      "Verification Data: Documents for KYC/AML compliance (e.g., passport, utility bills).",
    ],
  },
  {
    numero: "2.2",
    titulo: "Automatically Collected Data",
    contenido: [
      "Device & Usage Data: IP address, browser type, device identifiers, log files, pages visited.",
      "Cookies & Tracking: We use cookies to analyze trends and personalize content (see Section 6).",
    ],
  },
  {
    numero: "2.3",
    titulo: "Data from Third Parties",
    contenido: [
      "Brokerage Partners: Trade execution records, account balances.",
    ],
  },
  {
    numero: "3",
    titulo: "How We Use Your Information",
    contenido: [
      "We use your information to:",
      "Provide, operate, and secure the Platform;",
      "Verify your identity and comply with legal obligations (e.g., FINRA, SEC rules);",
      "Process transactions and generate tax documents;",
      "Communicate service updates, security alerts, or promotional offers (with consent);",
      "Improve Platform functionality and user experience.",
    ],
  },
  {
    numero: "4",
    titulo: "How We Share Your Information",
    contenido: [
      "We may disclose your information to:",
      "Regulatory Authorities: As required by law (e.g., SEC, FINRA, IRS);",
      "Service Providers: Payment processors, cloud hosting providers, fraud detection services;",
      "Legal Compliance: In response to subpoenas, court orders, or legal investigations.",
      "We do not sell your personal information to third parties for marketing purposes.",
    ],
  },
  {
    numero: "5",
    titulo: "Data Security",
    contenido: [
      "We implement SSL encryption, multi-factor authentication (MFA), and regular security audits.",
      "Sensitive data (e.g., SSN, bank details) is stored in encrypted databases with limited access.",
    ],
  },
  {
    numero: "6",
    titulo: "Cookies & Tracking Technologies",
    contenido: [
      "Essential Cookies: Required for Platform functionality (e.g., login sessions).",
      "Analytics Cookies: We use Google Analytics to track usage patterns (opt-out via browser settings).",
      "Advertising Cookies: If applicable, describe third-party ad networks (e.g., DoubleClick).",
    ],
  },
  {
    numero: "7",
    titulo: "Your Rights & Choices",
    contenido: [],
  },
  {
    numero: "7.1",
    titulo: "Access & Correction",
    contenido: [
      "You may review or update your account information via the Platform's dashboard.",
    ],
  },
  {
    numero: "7.2",
    titulo: "Data Deletion",
    contenido: [
      "Request deletion of non-essential data by contacting us, subject to legal retention requirements.",
    ],
  },
  {
    numero: "7.4",
    titulo: "CCPA Rights (California Residents)",
    contenido: [
      "California residents may:",
      'Request disclosure of data categories collected in the past 12 months;',
      'Opt out of the "sale" of personal information (if applicable);',
      "Non-discrimination for exercising rights.",
    ],
  },
  {
    numero: "8",
    titulo: "Data Retention",
    contenido: [
      "We retain your information:",
      "As long as your account is active;",
      "To comply with legal obligations (e.g., SEC Rule 17a-4 requires 7-year retention of trading records);",
      "To resolve disputes or enforce agreements.",
    ],
  },
  {
    numero: "9",
    titulo: "Children's Privacy",
    contenido: [
      "The Platform is not intended for users under 18. We do not knowingly collect data from minors.",
    ],
  },
  {
    numero: "10",
    titulo: "International Data Transfers",
    contenido: [
      "Data is processed in the United States. By using the Platform, you consent to transfer and storage in the U.S.",
    ],
  },
  {
    numero: "11",
    titulo: "Changes to This Policy",
    contenido: [
      "We will notify you of material changes via email or Platform notifications. Continued use constitutes acceptance.",
    ],
  },
];
