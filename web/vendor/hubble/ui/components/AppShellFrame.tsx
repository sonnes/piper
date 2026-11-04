import type { ReactNode } from "react";

export function AppShellFrame({
	toolbar,
	sidebar,
	children,
}: {
	toolbar: ReactNode;
	sidebar?: ReactNode;
	children: ReactNode;
}) {
	return (
		<main className="flex h-dvh flex-col bg-background text-foreground">
			{toolbar}
			<div className="flex min-h-0 flex-1 overflow-hidden">
				{sidebar}
				<section className="flex-1 overflow-hidden" aria-live="polite">
					{children}
				</section>
			</div>
		</main>
	);
}
