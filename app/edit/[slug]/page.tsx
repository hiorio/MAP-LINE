import { Editor } from './Editor';

export default async function EditPage({ params }: { params: Promise<{ slug: string }> }) {
  const { slug } = await params;
  return <Editor slug={slug} />;
}
