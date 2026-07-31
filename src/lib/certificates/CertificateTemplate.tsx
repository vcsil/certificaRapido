import { Document, Page, Text, View, Image, StyleSheet, Font } from "@react-pdf/renderer";

// @react-pdf/renderer desenha o PDF programaticamente — sem Puppeteer,
// sem navegador headless, ideal para função serverless free tier.
// Para trocar de "layout", edite este componente ou crie variações dele.

const styles = StyleSheet.create({
  page: {
    padding: 0,
    fontFamily: "Helvetica",
    backgroundColor: "#0B1220",
  },
  border: {
    margin: 24,
    flex: 1,
    borderWidth: 1.5,
    borderColor: "#3DDC97",
    padding: 48,
    justifyContent: "space-between",
  },
  eyebrow: {
    fontSize: 11,
    letterSpacing: 3,
    color: "#3DDC97",
    textTransform: "uppercase",
  },
  title: {
    fontSize: 30,
    color: "#FFFFFF",
    marginTop: 8,
    fontFamily: "Helvetica-Bold",
  },
  body: {
    marginTop: 28,
  },
  name: {
    fontSize: 24,
    color: "#FFFFFF",
    fontFamily: "Helvetica-Bold",
    marginBottom: 10,
  },
  paragraph: {
    fontSize: 12,
    color: "#B7C0D8",
    lineHeight: 1.6,
  },
  footer: {
    flexDirection: "row",
    justifyContent: "space-between",
    alignItems: "flex-end",
  },
  footerText: {
    fontSize: 9,
    color: "#7C879E",
  },
  hash: {
    fontSize: 10,
    color: "#3DDC97",
    fontFamily: "Courier",
    marginTop: 2,
  },
  qrCode: {
    width: 64,
    height: 64,
  },
});

export interface CertificateData {
  participantName: string;
  eventTitle: string;
  workloadHours: number;
  instructor?: string | null;
  issuedAtLabel: string; // já formatada em pt-BR
  validationHash: string;
  qrCodeDataUrl: string;
  orgName: string;
}

export function CertificateTemplate({ data }: { data: CertificateData }) {
  return (
    <Document>
      <Page size="A4" orientation="landscape" style={styles.page}>
        <View style={styles.border}>
          <View>
            <Text style={styles.eyebrow}>{data.orgName}</Text>
            <Text style={styles.title}>Certificado de Conclusão</Text>
            <View style={styles.body}>
              <Text style={styles.name}>{data.participantName}</Text>
              <Text style={styles.paragraph}>
                concluiu com êxito o curso "{data.eventTitle}", com carga
                horária de {data.workloadHours} horas
                {data.instructor ? `, ministrado por ${data.instructor}` : ""}.
              </Text>
              <Text style={styles.paragraph}>Emitido em {data.issuedAtLabel}.</Text>
            </View>
          </View>

          <View style={styles.footer}>
            <View>
              <Text style={styles.footerText}>Código de validação</Text>
              <Text style={styles.hash}>{data.validationHash}</Text>
              <Text style={styles.footerText}>Valide em {process.env.NEXT_PUBLIC_APP_URL}/validar</Text>
            </View>
            {/* eslint-disable-next-line jsx-a11y/alt-text */}
            <Image style={styles.qrCode} src={data.qrCodeDataUrl} />
          </View>
        </View>
      </Page>
    </Document>
  );
}
