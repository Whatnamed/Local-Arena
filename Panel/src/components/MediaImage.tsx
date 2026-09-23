import { useEffect, useState, type ImgHTMLAttributes } from "react";
import bundledMedia from "../data/bundledPickerMedia.json";

const localImages = new Map(bundledMedia.map((image) => [image.original, image.path]));

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

  const source = props.src && (localImages.get(props.src) ?? props.src.replace(
    "https://community.akamai.steamstatic.com/", "https://community.fastly.steamstatic.com/"));
  return <img {...props} src={source} onError={() => setFailed(true)} />;
}
