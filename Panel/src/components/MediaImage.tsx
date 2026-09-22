import { useEffect, useState, type ImgHTMLAttributes } from "react";

type Props = ImgHTMLAttributes<HTMLImageElement> & {
  fallbackLabel?: string;
};

export default function MediaImage({ fallbackLabel = "Image unavailable", ...props }: Props) {
  const [failed, setFailed] = useState(!props.src);

  useEffect(() => setFailed(!props.src), [props.src]);

  if (failed) {
    return <span className={`media-image-fallback ${props.className ?? ""}`} role="img" aria-label={props.alt}>
      {fallbackLabel}
    </span>;
  }

  return <img {...props} onError={() => setFailed(true)} />;
}
